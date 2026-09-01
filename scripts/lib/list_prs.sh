#! /bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=SCRIPT_DIR/common.sh
source "${SCRIPT_DIR}/common.sh"

DEFAULT_STATE="merged"
DEFAULT_LIMIT=1000

usage() {
  cat <<'EOF'
Usage: list_prs.sh [options]

Lists PR numbers for a repo, most-recent-first, one per line.

Options:
  --path PATH        Directory to detect the repo from (default: current directory).
  --repo OWNER/NAME   Explicit repo, skips detection from --path.
  --state STATE       open|closed|merged|all (default: merged).
  --limit N           Max PR count. 0 means no cap. (default: 1000).
  --all               Shorthand for --limit 0 (no cap).
  -h, --help          Show this help.

Exit codes:
  0  success (or no matching PRs).
  1  usage or environment error.
  2  PR count exceeds an unset (default) --limit; re-run with an explicit
     --limit to proceed (see the printed NEEDS_INPUT message).
EOF
}

list_pr_numbers() {
  local repo="$1"
  local state="$2"
  local probe_limit="$3"
  gh pr list -R "${repo}" --state "${state}" --limit "${probe_limit}" \
    --json number --jq '.[].number'
}

main() {
  local target_path="${PWD}"
  local repo=""
  local state="${DEFAULT_STATE}"
  local limit="${DEFAULT_LIMIT}"
  local limit_explicit="false"

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

  if [[ -z "${repo}" ]]; then
    repo="$(detect_repo "${target_path}")"
  fi

  local probe_limit
  if [[ "${limit}" -eq 0 ]]; then
    probe_limit=1000000
  else
    probe_limit=$(( limit + 1 ))
  fi

  local numbers_file
  numbers_file="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${numbers_file}'" EXIT

  list_pr_numbers "${repo}" "${state}" "${probe_limit}" >"${numbers_file}"

  local found_count
  found_count="$(wc -l <"${numbers_file}" | tr -d ' ')"

  if [[ "${found_count}" -eq 0 ]]; then
    printf 'no %s PRs found for %s\n' "${state}" "${repo}" >&2
    exit 0
  fi

  if [[ "${limit_explicit}" != "true" && "${found_count}" -gt "${limit}" ]]; then
    printf 'NEEDS_INPUT: %s has more than %d %s PRs.\n' "${repo}" "${limit}" "${state}" >&2
    printf 'Re-run with --limit %d for the most recent %d, or --limit 0 for all.\n' "${limit}" "${limit}" >&2
    exit 2
  fi

  if [[ "${limit}" -ne 0 ]]; then
    head -n "${limit}" "${numbers_file}"
  else
    cat "${numbers_file}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
