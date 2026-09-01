# Comments to Rules

A Claude Code skill. 
It turns a GitHub repo's PR review-comment history into per-language coding-style rule files. 
It adds rules inferred from the local
codebase. 
It can then run a review against the result.

See [SKILL.md](SKILL.md) for the full procedure and [PLAN.md](PLAN.md) for
the design plan.

## Requirements

- [Claude Code](https://claude.com/claude-code).
- The [`gh` CLI](https://cli.github.com/), installed and authenticated
  (`gh auth login`). This is a hard requirement — see
  [Limitations](#limitations).
- `jq`.
- `bash`, and the `timeout` command (from GNU coreutils — present by
  default on Linux, and on macOS with coreutils installed).

## Install

Copy or symlink this repo into your Claude Code skills directory:

```bash
git clone <this-repo-url> ~/.claude/skills/comments-to-rules
```

Or, if you already have a local clone:

```bash
ln -s /path/to/comments-to-rules ~/.claude/skills/comments-to-rules
```

Restart Claude Code, or start a new session, so it picks up the skill.

## Run

Open Claude Code in the repo you want rules for — the **target repo**, a
different repo from this skill's own repo. Then ask for it in plain
language, for example:

```text
Generate coding-style rules from our PR review history
```

Claude Code matches this request against the skill's trigger description,
then runs the procedure in [SKILL.md](SKILL.md):

1. Fetches merged-PR review comments through `gh`.
2. Filters and groups them into per-language rules.
3. Adds rules inferred from the local codebase.
4. Writes `.claude/rules/code-style-{language}.md` files into the target
   repo.
5. Offers to run a review of the target repo against the new rules.

## Limitations

- **Requires `gh`, installed and authenticated.** The fetch step calls the
  `gh` CLI for every GitHub API request. If `gh` is missing, or
  `gh auth status` fails, the skill stops and tells you how to fix it. It
  does not fall back to an unauthenticated method. See the
  [Future Work](PLAN.md#future-work) section of `PLAN.md` for research into
  a `gh`-free fetch path — plain `curl` or `wget` against public repos.
- GitHub only, for now. See the same `PLAN.md` section for notes on
  supporting GitLab, Bitbucket, and self-hosted Git forges.
- Linux only, tested. macOS ships `bash` 3.2 and no `timeout` command by
  default. `scripts/lib/fetch_pr_comments.sh` needs `timeout` to kill a
  stuck fetch. See the macOS support note in
  [PLAN.md](PLAN.md#future-work).
- Fetches merged PRs by default, most recent 1000. Pass `--all` to
  `scripts/fetch_comments.sh` for no cap, or ask Claude to use it. See
  [references/fetch-plan.md](references/fetch-plan.md) for every flag.

## See also

- [SKILL.md](SKILL.md) — the procedure Claude Code follows.
- [references/fetch-plan.md](references/fetch-plan.md) — full spec for the
  fetch pipeline.
- [references/rule-template.md](references/rule-template.md) — output
  format for the generated rule files.

## Example Outputs:

```
Rule files complete.

Wrote .claude/rules/code-style-typescript.md, code-style-sql.md, code-style-yaml.md, code-style-terraform.md, code-style-json.md (5 files)
Languages: typescript, sql, terraform, yaml, json
297 merged PRs fetched, 42 comments survived length filtering, 20 of those used to create rules
31 rules created total (Terraform and JSON came entirely from local inference — no PR history for those languages)
~130K tokens used this run (rough estimate, mostly the two background research agents — run /cost for an exact figure)
Skipped markdown and shell — too few files in the repo (3 and 2) to be worth dedicated rule files.
```

```
All 8 files written. Rule-file writing done.

Summary

Wrote 8 files: code-style-python.md, code-style-typescript.md, code-style-yaml.md, code-style-shell.md, code-style-markdown.md, code-style-json.md, code-style-terraform.md, code-style-ros-interfaces.md
Languages covered: python (+ ROS launch, notebooks), typescript/tsx (+ javascript), yaml/yml, shell/bash, markdown, json, terraform/tfvars, ROS .msg/.srv
PRs fetched: 2250 merged (all of them, per your choice)
Comments fetched: 3997 across 43 language groups (post length-filter)
Comments used: ~85 shaped a PR-derived rule (13 python, 19 typescript, 9 yaml, 14 shell, 11 markdown, 4 json, 10 terraform, 4 ros-interfaces)
Rules created total: ~120 (PR-derived + locally inferred combined, across all 8 files)
Tokens used: rough estimate ~950K tokens this run (dump reads + local scans + file writes, /4 char proxy) — not billed figure, run /cost for exact
Languages skipped: csv, xml, cfg, cpp, ipynb (standalone), js (standalone) — each had too little PR signal and too few files to warrant a dedicated file; js/ipynb/launch content got folded into typescript/python instead
```