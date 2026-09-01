#! /bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=SCRIPT_DIR/common.sh
source "${SCRIPT_DIR}/common.sh"

DEFAULT_CONCURRENCY=20
DEFAULT_PR_TIMEOUT=30

usage() {
  cat <<'EOF'
Usage: fetch_pr_comments.sh --repo OWNER/NAME --out-dir DIR [options]

Fetches PR review comments for a list of PR numbers (one per line, from
--numbers-file or stdin) and writes one raw JSONL file per PR into --out-dir.

If interrupted (Ctrl-C) partway through, stops after the batch in progress
and leaves already-fetched PRs' files in place, printing the PR range that
was not yet fetched so the caller can re-run for just that range later.

Options:
  --repo OWNER/NAME     Repo to fetch from. Required.
  --out-dir DIR         Directory to write pr-<number>.jsonl files into. Required.
  --numbers-file PATH   File of PR numbers, one per line. Default: read stdin.
  --concurrency N       Parallel PR fetches (default: 20).
  --timeout N           Per-PR fetch timeout in seconds (default: 30). A stuck
                         request is killed and retried rather than hanging the
                         whole batch.
  -h, --help            Show this help.
EOF
}

fetch_one_pr_comments() {
  local repo="$1"
  local pr_number="$2"
  local out_dir="$3"
  local timeout_secs="$4"
  local attempt=1
  local max_attempts=4
  local backoff=5
  local out_file="${out_dir}/pr-${pr_number}.jsonl"
  local rc

  while (( attempt <= max_attempts )); do
    if timeout "${timeout_secs}" gh api "repos/${repo}/pulls/${pr_number}/comments" --paginate \
      --jq ".[] | {pr: ${pr_number}, path, author: .user.login, created_at, body,
        diff_hunk: (if (.body | contains(\"\`\`\`suggestion\")) then .diff_hunk else null end)}" \
      >"${out_file}" 2>"${out_file}.err"; then
      rc=0
    else
      rc=$?
    fi

    if [[ "${rc}" -eq 0 ]]; then
      rm -f "${out_file}.err"
      return 0
    fi

    if [[ "${rc}" -eq 124 ]] \
      || grep -qE '(HTTP 403|HTTP 429|rate limit|abuse detection)' "${out_file}.err" 2>/dev/null; then
      sleep "${backoff}"
      backoff=$(( backoff * 3 ))
      attempt=$(( attempt + 1 ))
      continue
    fi

    cat "${out_file}.err" >&2
    return 1
  done

  printf 'error: giving up on PR #%s after %d attempts (timeout or rate limit)\n' \
    "${pr_number}" "${max_attempts}" >&2
  return 1
}

# Fetches comments for every PR number in numbers_file, in batches of 100,
# printing progress (first/last PR in the batch, running total) as it goes.
#
# Ctrl-C (or a TERM) stops it after the in-progress batch instead of losing
# everything: each PR's comments are already written to out_dir as soon as
# that PR completes, so the caller sets a trap that flips INTERRUPTED=true,
# and this loop checks that flag between batches and stops cleanly, printing
# the PR range that was not yet fetched.
fetch_all_comments() {
  local repo="$1"
  local numbers_file="$2"
  local out_dir="$3"
  local concurrency="$4"
  local timeout_secs="$5"
  local batch_size=100
  local total_count batch_dir
  local batch_index=0 processed=0 batch_count first_pr last_pr

  total_count="$(wc -l <"${numbers_file}" | tr -d ' ')"
  batch_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${batch_dir}'" RETURN
  split -l "${batch_size}" -d -a 4 "${numbers_file}" "${batch_dir}/batch-"

  local batch_files=("${batch_dir}"/batch-*)
  local total_batches="${#batch_files[@]}"

  export -f fetch_one_pr_comments
  for batch_file in "${batch_files[@]}"; do
    batch_index=$(( batch_index + 1 ))
    batch_count="$(wc -l <"${batch_file}" | tr -d ' ')"
    first_pr="$(head -n1 "${batch_file}")"
    last_pr="$(tail -n1 "${batch_file}")"
    printf 'fetching comments for PR #%s .. #%s (batch %d/%d, %d PRs)\n' \
      "${first_pr}" "${last_pr}" "${batch_index}" "${total_batches}" "${batch_count}"

    xargs -a "${batch_file}" -P "${concurrency}" -I{} \
      bash -c 'fetch_one_pr_comments "$1" "$2" "$3" "$4"' _ "${repo}" {} "${out_dir}" "${timeout_secs}" \
      || true

    processed=$(( processed + batch_count ))
    printf '  %d/%d PRs done\n' "${processed}" "${total_count}"

    if [[ "${INTERRUPTED:-false}" == "true" ]]; then
      local remaining=("${batch_files[@]:${batch_index}}")
      if [[ "${#remaining[@]}" -gt 0 ]]; then
        local resume_first resume_last
        resume_first="$(head -n1 "${remaining[0]}")"
        resume_last="$(tail -n1 "${remaining[-1]}")"
        printf 'interrupted after batch %d/%d — PR #%s down to #%s not fetched yet\n' \
          "${batch_index}" "${total_batches}" "${resume_first}" "${resume_last}"
        printf 'writing what was fetched so far; re-run later to fill in the rest\n'
      fi
      break
    fi
  done
}

main() {
  local repo="" out_dir="" numbers_file=""
  local concurrency="${DEFAULT_CONCURRENCY}"
  local timeout_secs="${DEFAULT_PR_TIMEOUT}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo="$2"
        shift 2
        ;;
      --repo=*)
        repo="${1#*=}"
        shift
        ;;
      --out-dir)
        out_dir="$2"
        shift 2
        ;;
      --out-dir=*)
        out_dir="${1#*=}"
        shift
        ;;
      --numbers-file)
        numbers_file="$2"
        shift 2
        ;;
      --numbers-file=*)
        numbers_file="${1#*=}"
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

  if [[ -z "${repo}" || -z "${out_dir}" ]]; then
    printf 'error: --repo and --out-dir are required\n' >&2
    usage >&2
    exit 1
  fi

  require_command gh "Install from https://cli.github.com/ and run: gh auth login"
  require_command timeout "coreutils should provide this; check your PATH"
  mkdir -p "${out_dir}"

  local numbers_input
  if [[ -n "${numbers_file}" ]]; then
    numbers_input="${numbers_file}"
  else
    numbers_input="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${numbers_input}'" EXIT
    cat >"${numbers_input}"
  fi

  INTERRUPTED="false"
  trap 'INTERRUPTED=true' INT TERM

  fetch_all_comments "${repo}" "${numbers_input}" "${out_dir}" "${concurrency}" "${timeout_secs}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
