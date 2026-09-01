---
paths:
  - "**/*.sh"
  - "**/*.bash"
  - "**/*.zsh"
---

# Shell Script Rules

Treat this as a going-forward convention, not a retrofit mandate. An
older script in this repo may not follow every rule below. Do not
rewrite an existing script only to match this convention, unless you
already have another reason to change that part of the script.

- Shebang: use `#! /bin/bash`.
  Only use `#!/bin/sh` when the script genuinely needs to run under a POSIX `sh`, not bash.

- For a script that runs in a CI/CD pipeline, for example under
  `.github/scripts`, start with `set -euo pipefail` right after the shebang:

```
#! /bin/bash
set -euo pipefail
```

For a file meant to be **sourced** into another script's shell (a
shared helper or library, for example `versions_lib.sh`), do not set
this. `source` runs in the caller's shell. `set -e` in a sourced file
would silently change the calling script's own error-handling
behaviour too.

- Wrap a script's logic in functions almost always. Guard the call
  that actually runs it behind a check for whether the script is
  running directly, not sourced:

```
main() {
  ...
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

This keeps every function sourceable and independently testable. A
test script, or another script that wants to reuse one function, can
`source` the file without triggering `main`. This avoids the need for
a separate entry-point file. The guarded block at the bottom should be
the only unconditionally-executed code in the file.

- Variable naming uses two tiers. This matches how the newer scripts
  split file-level config from working state:
  - `UPPER_SNAKE_CASE` for file-level constants and argv-derived config
    read once near the top of the script (paths, urls, flags).
  - `lower_snake_case` for working variables inside a function. Always
    declare these with `local`.

```
notLikeThis() {
  STAGING_DIR="$(mktemp -d)"
}

ratherLikeThis() {
  local staging_dir
  staging_dir="$(mktemp -d)"
}
```

- Always double-quote variable expansions. Prefer the `${var}` brace
  form when the expansion sits directly next to other text. This
  makes clear where the variable name ends. A variable standing alone
  does not need the braces:

```
# notLikeThis
rm -rf $STAGING_DIR/$package_name

# ratherLikeThis
rm -rf "${STAGING_DIR}/${package_name}"

# sometimesLikeThis
rm -f "$package_name"
```

  Braces are also required, regardless of adjacency, for a parameter
  expansion operator, for example a default value or a prefix/suffix
  strip:

```
STABILITY="${STABILITY:-test}"
code="${pair%%:*}"
```

- Function style: `name() {`, not `function name() {}`. Put the
  opening brace on the same line as the name.

- Prefer a complete `if` block over a `condition && command` or
  `condition || command` one-liner used for control flow:

```
# notLikeThis
[[ -f "${configPath}" ]] && rm "${configPath}"

# ratherLikeThis
if [[ -f "${configPath}" ]]; then
  rm "${configPath}"
fi
```

A one-liner hides the command's own exit status inside the `&&`/`||`
chain. Under `set -e` in particular, a failing right-hand command can
behave differently than it would inside an `if`. Either way, the
one-liner is easy to misread as "run this if that," when it actually
means "run this, and the whole line's status depends on both."

- Indent with two spaces.

- Argument parsing:
  - A script with one or two fixed, caller-controlled args: use plain
    positional params (`REPO=$1`, `TAG=$2`).
  - A script with `--flag`-style options: use a manual
    `while [[ $# -gt 0 ]]; do case "$1" in ... esac; shift; done` loop
    that supports both `--flag value` and `--flag=value`. Do not use
    `getopts` for this.

```
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stability)
      stability="$2"
      shift 2
      ;;
    --stability=*)
      stability="${1#*=}"
      shift
      ;;
    *)
      printf 'error: unknown argument %s\n' "$1" >&2
      exit 1
      ;;
  esac
done
```

- Do not write banner or section comments (`# ---- helpers ----`). Let
  function names and structure carry that instead. If a script
  already has them, leave them alone when your change does not touch
  that section. Ask the user before you remove them if you are
  actively refactoring or improving that file.

- Use `trap ... EXIT` for cleanup whenever a script creates a temp
  file or directory. This removes it even on an early `exit` or an
  error:

```
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
```

- To source a sibling script, resolve the current script's own
  directory first. Do not assume the caller's `cwd`:

```
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=SCRIPT_DIR/other.sh
source "${SCRIPT_DIR}/other.sh"
```

A hardcoded absolute path (for example `source /usr/local/lib/myapp/config.sh`)
is fine once a script is actually installed to a fixed system
location. That case differs from a repo-relative sibling import.
Either way, add a `# shellcheck source=` hint above the `source` line.
This hint lets shellcheck follow the source path when SC1091 is
disabled. It lets an editor do the same when the editor cannot
resolve the path on its own.

- Avoid an unnecessary `cd`. Pass the target path directly to the
  command instead (`unzip "${dir}/file.zip" -d "${dir}"` rather than
  `cd "${dir}" && unzip file.zip`). This also avoids a failure mode: a
  failed `cd` can silently leave the script in the wrong directory.

- Files end with exactly one trailing newline.
