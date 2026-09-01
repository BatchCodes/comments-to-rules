#! /bin/bash
# Shared constants and helpers. Sourced by the other scripts in this
# directory; not meant to be run directly.

RECORD_SEP=$'\x1e'
UNIT_SEP=$'\x1f'

require_command() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "${cmd}" &>/dev/null; then
    printf 'error: required command not found: %s\n%s\n' "${cmd}" "${hint}" >&2
    exit 1
  fi
}

detect_repo() {
  local path="$1"
  local remote_url owner_name
  remote_url="$(git -C "${path}" remote get-url origin 2>/dev/null)" || {
    printf 'error: no git remote "origin" found in %s\n' "${path}" >&2
    exit 1
  }
  owner_name="$(printf '%s\n' "${remote_url}" | sed -E \
    -e 's#^git@github\.com:##' \
    -e 's#^https://github\.com/##' \
    -e 's#\.git$##')"
  if [[ -z "${owner_name}" || "${owner_name}" != */* ]]; then
    printf 'error: could not parse owner/repo from remote url: %s\n' "${remote_url}" >&2
    exit 1
  fi
  printf '%s\n' "${owner_name}"
}
