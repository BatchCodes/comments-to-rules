#! /bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=SCRIPT_DIR/common.sh
source "${SCRIPT_DIR}/common.sh"

DEFAULT_CHUNK_SIZE=250

usage() {
  cat <<'EOF'
Usage: write_output.sh FORMATTED.txt --output PATH [options]

Reads the language-tagged record stream produced by format_comments.sh and
writes it out.

  - --output is an existing directory, or a path ending in /: writes
    PATH/<language>/comments-NNN.md, chunked at --chunk-size comments per file.
  - --output is any other path: writes a single markdown file, one section
    per language.

Options:
  --output PATH     Where to write. Required.
  --chunk-size N    Comments per chunk file in directory mode (default: 250).
                    Kept small deliberately: a downstream agent typically
                    reads a whole chunk file in one `Read` call, so a large
                    chunk means a large single context injection. 250 keeps
                    even a busy chunk file under roughly 5-8K tokens.
  -h, --help        Show this help.
EOF
}

# Directory mode: one subdirectory per language, chunked comments-NNN.md
# files inside each. Single awk pass — no per-comment process fork.
write_markdown_chunks() {
  local formatted_file="$1"
  local out_dir="$2"
  local chunk_size="$3"

  if [[ ! -s "${formatted_file}" ]]; then
    printf 'no review comments found on the fetched PRs\n'
    return 0
  fi

  printf 'writing comments to %s\n' "${out_dir}"

  awk -v RS="${RECORD_SEP}" -v US="${UNIT_SEP}" -v chunk_size="${chunk_size}" -v out_dir="${out_dir}" '
    length($0) == 0 { next }
    {
      pos = index($0, US)
      lang = substr($0, 1, pos - 1)
      block = substr($0, pos + 1)

      if ((count[lang] % chunk_size) == 0) {
        if (lang in fname) close(fname[lang])
        chunk_index[lang]++
        lang_dir = out_dir "/" lang
        if (!(lang in dirmade)) {
          system("mkdir -p \"" lang_dir "\"")
          dirmade[lang] = 1
        }
        fname[lang] = sprintf("%s/comments-%03d.md", lang_dir, chunk_index[lang])
        printf("writing %s chunk %03d to %s\n", lang, chunk_index[lang], fname[lang])
        printf("# PR Review Comments — %s (chunk %03d, newest first)\n\n", lang, chunk_index[lang]) > fname[lang]
      }

      print block "\n" >> fname[lang]
      count[lang]++
      total++
    }
    END {
      printf("wrote %d comment(s) across %d language group(s) in %s\n", total, length(count), out_dir)
      for (l in count) {
        printf("  %s: %d comment(s), %d chunk file(s)\n", l, count[l], chunk_index[l])
      }
    }
  ' "${formatted_file}"
}

# Single-file mode: one file, one section per language, in memory. Meant for
# the modest comment volumes a single explicit --output file implies.
write_markdown_single() {
  local formatted_file="$1"
  local out_file="$2"

  if [[ ! -s "${formatted_file}" ]]; then
    printf 'no review comments found on the fetched PRs\n'
    return 0
  fi

  printf 'writing comments to %s\n' "${out_file}"

  awk -v RS="${RECORD_SEP}" -v US="${UNIT_SEP}" -v out_file="${out_file}" '
    length($0) == 0 { next }
    {
      pos = index($0, US)
      lang = substr($0, 1, pos - 1)
      block = substr($0, pos + 1)
      if (!(lang in seen)) {
        seen[lang] = 1
        order[++n] = lang
      }
      buf[lang] = buf[lang] block "\n"
      count[lang]++
      total++
    }
    END {
      printf("# PR Review Comments (newest first, grouped by language)\n") > out_file
      for (i = 1; i <= n; i++) {
        l = order[i]
        printf("\n## Language: %s\n\n", l) >> out_file
        printf("%s", buf[l]) >> out_file
      }
      printf("wrote %d comment(s) across %d language group(s) to %s\n", total, n, out_file)
    }
  ' "${formatted_file}"
}

main() {
  local formatted_file="" output="" chunk_size="${DEFAULT_CHUNK_SIZE}"
  local positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        output="$2"
        shift 2
        ;;
      --output=*)
        output="${1#*=}"
        shift
        ;;
      --chunk-size)
        chunk_size="$2"
        shift 2
        ;;
      --chunk-size=*)
        chunk_size="${1#*=}"
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

  if [[ "${#positional[@]}" -ne 1 || -z "${output}" ]]; then
    printf 'error: expected FORMATTED.txt and --output PATH\n' >&2
    usage >&2
    exit 1
  fi
  formatted_file="${positional[0]}"

  local mode target
  if [[ -d "${output}" || "${output}" == */ ]]; then
    mode="dir"
    target="${output%/}"
    mkdir -p "${target}"
  else
    mode="file"
    target="${output}"
    mkdir -p "$(dirname "${target}")"
  fi

  if [[ "${mode}" == "dir" ]]; then
    write_markdown_chunks "${formatted_file}" "${target}" "${chunk_size}"
  else
    write_markdown_single "${formatted_file}" "${target}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
