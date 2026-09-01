# fetch_comments.sh — Design Spec

This is implemented as a pipeline under `scripts/`. `fetch_comments.sh` is a
thin entrypoint. It sources and orchestrates `scripts/lib/common.sh`,
`list_prs.sh`, `fetch_pr_comments.sh`, `format_comments.sh`, and
`write_output.sh`. Each `lib/` script also has its own `main()`, guarded by
the standard `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` check. This means any
stage runs standalone — piped into the next by hand — or through the
entrypoint. Keep this doc in sync as the pipeline evolves.

## Inputs

- Target repo: current directory by default, or a `--repo owner/name` or
  `--path` flag.
- `--state`: the PR state to fetch. Default `merged`. Accept `open`,
  `closed`, `merged`, or `all` as a named flag, so this is easy to widen
  later. Do not hardcode `merged` inline in the fetch logic.
- `--limit`: the max PR count. Default 1000. `--all` is shorthand for
  `--limit 0` — no cap. If the repo has more PRs than the default limit,
  print a `NEEDS_INPUT` message and exit with status 2, rather than prompt
  interactively. The calling agent asks the user, then re-runs with an
  explicit `--limit`.

## List (`lib/list_prs.sh`)

- Lists PR numbers for the target repo, most-recent-first, filtered by
  `--state`, one per line, to stdout.
- Owns the `NEEDS_INPUT` and exit-2 overflow check described above.

## Fetch (`lib/fetch_pr_comments.sh`)

- Reads PR numbers, from `--numbers-file` or stdin. Fetches review comments
  in batches of 100, through `xargs -P`, with a concurrency cap of 20 by
  default (`--concurrency` to override). Each PR fetch is a single
  `gh api --paginate --jq ...` call — no separate `jq` process piped after
  it. Writes one `pr-<number>.jsonl` file per PR, into `--out-dir`.
- Each PR fetch runs under `timeout` (default 30 seconds, `--timeout` to
  override). A single stalled network call used to hang the entire batch
  forever, because `xargs -P` waits for every child process before it
  returns. The timeout turns a hang into an ordinary, retryable failure.
- On a timeout, an HTTP 403 (GitHub's secondary rate limit, or abuse
  detection), or a 429 (too many requests): back off, then retry. Up to 4
  attempts, with exponential backoff starting at 5 seconds.
- Ctrl-C, or a TERM signal, sets a flag the script checks between batches.
  The run stops after the batch in progress, instead of losing everything.
  It prints the PR range it did not reach, so a later run can cover just
  that range. Already-fetched PRs keep their files — each PR's fetch writes
  its file the moment it completes, independent of the rest of the batch.

## Format (`lib/format_comments.sh`)

Reads the raw per-PR JSONL. Runs one `jq` process for the whole set — not
one fork per comment. That one process does three things:

- Drops a comment shorter than `--min-length` (default 20 characters). It
  measures this with any ` ```suggestion ` fenced block stripped out first,
  so a short note plus a large diff does not read as "long". The
  suggestion block itself stays in the output — only the length check
  ignores it. This is a mechanical noise filter. It catches `lgtm`, `nit`,
  `+1`, `done`, and similar comments. It does not replace the judgment-based
  filtering `SKILL.md` Step 2 still does — bot comments, and discussion with
  no action to take — because that needs judgment a regular expression
  cannot supply.
- Infers a language for each comment from its file extension, through a
  fixed extension-to-language map in the script. An unmapped extension
  falls back to the raw extension. A comment with no extension falls back
  to `other`. Keep this map in sync with the groupings the example rule
  files already use — for example, `.claude/rules/code-style-shell.md`
  covers `sh`, `bash`, and `zsh` as one `shell` group.
- Sorts every comment newest-first, then groups the result by language. The
  sort is stable, so the newest-first order holds within each group too.

The output is a stream of records: `<language><unit-sep><markdown
block><record-sep>`. The unit separator is `0x1f`. The record separator is
`0x1e`. This lets the write stage route each record by language, without it
having to re-parse JSON. The script uses `jq -j`, not `-r` — `-r` adds its
own newline after every output, which corrupted the record boundaries.

## Write (`lib/write_output.sh`)

- When `--output` names an existing directory, or a path that ends in `/`:
  writes `PATH/<language>/comments-NNN.md`, chunked at `--chunk-size`
  (default 250) comments per file, in one `awk` pass — not one fork per
  comment. The chunk size stays small on purpose. A downstream agent
  typically reads a whole chunk file in one `Read` call, so the chunk size
  directly bounds that call's cost. A transcript analysis of a real run
  found one `Read` of a 1000-comment chunk — the busiest language in that
  repo — costing about 13,700 tokens: roughly 12% of that session's real
  token cost, from a single tool call.
- When `--output` names any other path: writes a single markdown file, one
  section per language, newest-first within each section.
- Default, when the entrypoint's `--output` is omitted: a directory under
  `~/.cache/comments-to-rules/{owner}-{repo}/`.
- On a re-run, reuses existing output at the target location instead of
  fetching again, unless the caller passes `--force`.
- Reports progress to stdout throughout: the detected repo, the resolved
  output location, each fetch batch (first and last PR number in the batch,
  batch size, running total), and each output file as it writes it.

## Error handling

- `gh` not installed, or `gh auth status` fails: print a clear message,
  exit with a non-zero status. Do not attempt to fetch. Neither the
  script nor the calling agent runs `gh auth login` or `gh auth
  refresh` — the message tells the user to run it themselves.
- `jq` or `timeout` not installed: same.
- The target directory has no GitHub remote, or `gh repo view` fails: same.
- The repo has zero PRs matching `--state`: print that clearly, exit with
  status 0. This is not an error — `SKILL.md` Step 1 handles it by skipping
  to Step 3.

## Future: non-GitHub remotes

Everything above is GitHub-specific: the `gh` CLI, GitHub's REST API shape,
and GitHub's `HTTP 403`/`429` semantics. Supporting GitLab, Bitbucket, or a
self-hosted Gitea or Forgejo instance means two things: detect the remote
host, instead of assuming GitHub, and swap in a host-specific list-and-fetch
implementation behind the same `list_pr_numbers` and `fetch_one_pr_comments`
interface. Not planned for the first version. This note exists so the
`lib/` split — rather than one large script — stays a deliberate choice: a
second host's fetch and list scripts could sit beside the GitHub ones, and
share `format_comments.sh` and `write_output.sh` unchanged, because those
two scripts only handle the already-normalized `{pr, path, author,
created_at, body}` shape.
