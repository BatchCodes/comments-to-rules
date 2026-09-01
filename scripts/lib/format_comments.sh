#! /bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=SCRIPT_DIR/common.sh
source "${SCRIPT_DIR}/common.sh"

DEFAULT_MIN_LENGTH=20

# Extension -> language name. Extensions not listed here fall back to the
# raw extension as the language name; a path with no extension falls back
# to "other". Keep this in sync with the groupings the example rule files
# already use (.claude/rules/code-style-shell.md covers sh/bash/zsh as one
# "shell" group, for example).
EXTENSION_MAP_JSON='{
  "sh": "shell", "bash": "shell", "zsh": "shell",
  "md": "markdown", "markdown": "markdown",
  "py": "python",
  "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
  "ts": "typescript", "tsx": "typescript",
  "go": "go",
  "rs": "rust",
  "rb": "ruby",
  "java": "java",
  "kt": "kotlin", "kts": "kotlin",
  "c": "c", "h": "c",
  "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp",
  "cs": "csharp",
  "php": "php",
  "swift": "swift",
  "yml": "yaml", "yaml": "yaml",
  "json": "json",
  "toml": "toml",
  "sql": "sql",
  "tf": "terraform",
  "proto": "protobuf"
}'

usage() {
  cat <<'EOF'
Usage: format_comments.sh INPUT.jsonl OUTPUT.txt [options]

Reads raw comment JSONL (one {pr, path, author, created_at, body} object per
line), and writes a formatted, filtered, language-tagged stream:

  - Drops comments shorter than --min-length, measured with any ```suggestion
    fenced block stripped out first (a short note plus a large diff should
    not read as "long"). The suggestion block itself is kept in the output.
  - Groups by language (inferred from the file extension in `path`), newest
    comment first within each group.
  - Each output record is: <language><unit-sep><markdown block><record-sep>
    (unit-sep = 0x1f, record-sep = 0x1e) so a downstream writer can route
    records to per-language files without re-parsing JSON.

Options:
  --min-length N   Minimum comment length to keep (default: 20).
  -h, --help       Show this help.
EOF
}

sort_and_format_comments() {
  local combined_jsonl="$1"
  local formatted_file="$2"
  local min_length="$3"

  jq -s -j \
    --arg rsep "${RECORD_SEP}" \
    --arg usep "${UNIT_SEP}" \
    --argjson extmap "${EXTENSION_MAP_JSON}" \
    --argjson minlen "${min_length}" '
    def suggestion_stripped: (.body // "") | gsub("(?s)```suggestion.*?```"; "");
    def extension:
      ((.path // "") | split("/") | last | split(".")) as $parts
      | if ($parts | length) > 1 then ($parts[-1] | ascii_downcase) else "" end;
    def language: extension as $e | if $e == "" then "other" else ($extmap[$e] // $e) end;

    map(select((suggestion_stripped | length) >= $minlen))
    | map(. + {language: language})
    | sort_by(.created_at) | reverse
    | group_by(.language) | sort_by(.[0].language)
    | .[][]
    | (.language + $usep +
       "## PR #\(.pr) — \(.path // "unknown path")\n\n- author: \(.author)\n- date: \(.created_at)\n\n\(.body)\n"
       + $rsep)
  ' "${combined_jsonl}" >"${formatted_file}"
}

main() {
  local input="" output="" min_length="${DEFAULT_MIN_LENGTH}"
  local positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --min-length)
        min_length="$2"
        shift 2
        ;;
      --min-length=*)
        min_length="${1#*=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [[ "${#positional[@]}" -ne 2 ]]; then
    printf 'error: expected INPUT.jsonl and OUTPUT.txt\n' >&2
    usage >&2
    exit 1
  fi
  input="${positional[0]}"
  output="${positional[1]}"

  sort_and_format_comments "${input}" "${output}" "${min_length}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
