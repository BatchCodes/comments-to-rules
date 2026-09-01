#! /bin/bash
set -euo pipefail

# Each lib/*.sh below also resolves its own SCRIPT_DIR when sourced (to find
# common.sh as a sibling), which clobbers this one — so this uses its own
# name rather than SCRIPT_DIR to survive all four sources.
MAIN_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=MAIN_SCRIPT_DIR/lib/common.sh
source "${MAIN_SCRIPT_DIR}/lib/common.sh"
# shellcheck source=MAIN_SCRIPT_DIR/lib/list_prs.sh
source "${MAIN_SCRIPT_DIR}/lib/list_prs.sh"
# shellcheck source=MAIN_SCRIPT_DIR/lib/fetch_pr_comments.sh
source "${MAIN_SCRIPT_DIR}/lib/fetch_pr_comments.sh"
# shellcheck source=MAIN_SCRIPT_DIR/lib/format_comments.sh
source "${MAIN_SCRIPT_DIR}/lib/format_comments.sh"
# shellcheck source=MAIN_SCRIPT_DIR/lib/write_output.sh
source "${MAIN_SCRIPT_DIR}/lib/write_output.sh"

DEFAULT_STATE="merged"
DEFAULT_LIMIT=1000

usage() {
  cat <<'EOF'
Usage: fetch_comments.sh [options]

Fetches PR review comments for a GitHub repo via `gh`, filters and groups
them by language, and writes a markdown dump.

Runs the pipeline in lib/: list_prs.sh -> fetch_pr_comments.sh ->
format_comments.sh -> write_output.sh. Each of those can also be run on its
own; see each script's own --help.

Options:
  --path PATH        Directory to detect the repo from (default: current directory).
  --repo OWNER/NAME    Explicit repo, skips detection from --path.
  --state STATE        PR state to fetch: open|closed|merged|all (default: merged).
  --limit N            Max PR count. 0 means no cap. (default: 1000).
  --all                Shorthand for --limit 0 (fetch every matching PR).
  --output PATH        Where to write the comment dump. An existing directory (or
                        a path ending in /) gets comments-NNN.md files chunked
                        per language inside it. Any other path is treated as a
                        single output file, grouped into per-language sections.
                        Default: a directory under ~/.cache/comments-to-rules/.
  --concurrency N      Parallel PR fetches (default: 20).
  --timeout N          Per-PR fetch timeout in seconds (default: 30). Prevents
                        one stuck request from hanging the whole run.
  --min-length N        Minimum comment length to keep, ```suggestion blocks
                        excluded from the count (default: 20).
  --force              Ignore any existing output, fetch fresh.
  -h, --help            Show this help.

If interrupted (Ctrl-C), stops after the batch in progress and writes
whatever was fetched so far, printing the PR range that was skipped so you
can re-run later to fill it in.

Exit codes:
  0  success (or existing output reused, or no matching PRs).
  1  usage or environment error (missing gh/jq, no auth, no remote).
  2  PR count exceeds --limit; re-run with an explicit --limit to proceed
     (see the printed NEEDS_INPUT message for the exact count found).
EOF
}

main() {
  local target_path="${PWD}"
  local repo=""
  local state="${DEFAULT_STATE}"
  local limit="${DEFAULT_LIMIT}"
  local limit_explicit="false"
  local force="false"
  local output_arg=""
  local concurrency="${DEFAULT_CONCURRENCY}"
  local timeout_secs="${DEFAULT_PR_TIMEOUT}"
  local min_length="${DEFAULT_MIN_LENGTH}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        target_path="$2"
        shift 2
        ;;
      --path=*)
        target_path="${1#*=}"
        shift
        ;;
      --repo)
        repo="$2"
        shift 2
        ;;
      --repo=*)
        repo="${1#*=}"
        shift
        ;;
      --state)
        state="$2"
        shift 2
        ;;
      --state=*)
        state="${1#*=}"
        shift
        ;;
      --limit)
        limit="$2"
        limit_explicit="true"
        shift 2
        ;;
      --limit=*)
        limit="${1#*=}"
        limit_explicit="true"
        shift
        ;;
      --all)
        limit=0
        limit_explicit="true"
        shift
        ;;
      --output)
        output_arg="$2"
        shift 2
        ;;
      --output=*)
        output_arg="${1#*=}"
        shift
        ;;
      --concurrency)
        concurrency="$2"
        shift 2
        ;;
      --concurrency=*)
        concurrency="${1#*=}"
        shift
        ;;
      --timeout)
        timeout_secs="$2"
        shift 2
        ;;
      --timeout=*)
        timeout_secs="${1#*=}"
        shift
        ;;
      --min-length)
        min_length="$2"
        shift 2
        ;;
      --min-length=*)
        min_length="${1#*=}"
        shift
        ;;
      --force)
        force="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'error: unknown argument %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  case "${state}" in
    open|closed|merged|all) ;;
    *)
      printf 'error: --state must be one of open|closed|merged|all, got: %s\n' "${state}" >&2
      exit 1
      ;;
  esac

  require_command gh "Install from https://cli.github.com/ and run: gh auth login"
  require_command jq "Install jq (e.g. apt install jq / brew install jq)"
  require_command timeout "coreutils should provide this; check your PATH"

  if ! gh auth status &>/dev/null; then
    printf 'error: gh is not authenticated. Run: gh auth login\n' >&2
    exit 1
  fi

  if [[ -z "${repo}" ]]; then
    repo="$(detect_repo "${target_path}")"
  fi
  printf 'repo: %s\n' "${repo}"

  local output_mode output_target
  if [[ -z "${output_arg}" ]]; then
    output_mode="dir"
    output_target="${HOME}/.cache/comments-to-rules/${repo//\//-}"
  elif [[ -d "${output_arg}" || "${output_arg}" == */ ]]; then
    output_mode="dir"
    output_target="${output_arg%/}"
  else
    output_mode="file"
    output_target="${output_arg}"
  fi
  printf 'output: %s (%s)\n' "${output_target}" "${output_mode}"

  if [[ "${output_mode}" == "dir" ]]; then
    if [[ "${force}" != "true" && -d "${output_target}" ]] \
      && find "${output_target}" -mindepth 1 -name 'comments-*.md' -print -quit | grep -q .; then
      printf 'reusing existing comment dump: %s\n' "${output_target}"
      printf 'run with --force to fetch fresh\n'
      exit 0
    fi
    mkdir -p "${output_target}"
  else
    if [[ "${force}" != "true" && -s "${output_target}" ]]; then
      printf 'reusing existing comment dump: %s\n' "${output_target}"
      printf 'run with --force to fetch fresh\n'
      exit 0
    fi
    mkdir -p "$(dirname "${output_target}")"
  fi

  local work_dir
  work_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${work_dir}'" EXIT

  local probe_limit
  if [[ "${limit}" -eq 0 ]]; then
    probe_limit=1000000
  else
    probe_limit=$(( limit + 1 ))
  fi

  local numbers_file="${work_dir}/pr-numbers.txt"
  list_pr_numbers "${repo}" "${state}" "${probe_limit}" >"${numbers_file}"

  local found_count
  found_count="$(wc -l <"${numbers_file}" | tr -d ' ')"

  if [[ "${found_count}" -eq 0 ]]; then
    printf 'no %s PRs found for %s\n' "${state}" "${repo}"
    exit 0
  fi

  if [[ "${limit_explicit}" != "true" && "${found_count}" -gt "${limit}" ]]; then
    printf 'NEEDS_INPUT: %s has more than %d %s PRs.\n' "${repo}" "${limit}" "${state}"
    printf 'Re-run with --limit %d for the most recent %d, or --limit 0 for all.\n' "${limit}" "${limit}"
    exit 2
  fi

  if [[ "${limit}" -ne 0 ]]; then
    head -n "${limit}" "${numbers_file}" >"${numbers_file}.trimmed"
    mv "${numbers_file}.trimmed" "${numbers_file}"
  fi

  local comments_dir="${work_dir}/comments"
  mkdir -p "${comments_dir}"

  INTERRUPTED="false"
  trap 'INTERRUPTED=true' INT TERM

  fetch_all_comments "${repo}" "${numbers_file}" "${comments_dir}" "${concurrency}" "${timeout_secs}"

  local combined_jsonl="${work_dir}/combined.jsonl"
  find "${comments_dir}" -name '*.jsonl' -print0 | xargs -0 cat >"${combined_jsonl}" 2>/dev/null || true

  local formatted_file="${work_dir}/formatted.txt"
  sort_and_format_comments "${combined_jsonl}" "${formatted_file}" "${min_length}"

  if [[ "${output_mode}" == "dir" ]]; then
    write_markdown_chunks "${formatted_file}" "${output_target}" "${DEFAULT_CHUNK_SIZE}"
  else
    write_markdown_single "${formatted_file}" "${output_target}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
