---
name: comments-to-rules
description: "Use when a user wants to turn a GitHub repo's PR review comment history into coding-style rule files for that repo — e.g. 'turn our PR comments into style rules', 'generate coding rules from our review history', 'build .claude/rules from past PR feedback'. Fetches merged-PR review comments via `gh`, filters them into actionable per-language rules, adds rules inferred from the local codebase, and optionally runs a review against the result. Requires `gh` (authenticated) and `jq`. Not for reviewing a single PR or diff — see the `code-review` skill for that."
version: 0.1.0
---

# Comments to Rules

This skill turns a repo's PR review-comment history into per-language coding-style rule files. It adds rules inferred from the local codebase. It then offers to run a review against the result.

Run this skill against a **target repo**: the directory the user works in now, or a path or remote they name. This skill lives in a separate repo. You run it once, on demand. It does not install into the target repo.

## When to Use This Skill

- The user asks to generate, build, or update coding-style rules from PR review history.
- The user wants `.claude/rules/` filled from past code-review feedback instead of writing it by hand.
- The user asks what conventions their reviewers actually enforce, and wants that turned into something an agent can follow.

Do not use this skill to review one specific PR or diff — use `code-review` for that. Do not use it for general repo documentation — use `init` for that.

## Prerequisites

Check these before you start. If any check fails, stop and give a clear message.

- `gh` is installed and authenticated (`gh auth status`).
- `jq` is installed.
- The target directory is a git repo with a GitHub remote (`gh repo view` succeeds there).

If `gh auth status` fails, do not run `gh auth login` or `gh auth refresh` yourself. Tell the user to run it, then stop. These commands can open an interactive browser flow or a device code prompt — only the user should start that.

## Procedure

### Step 1 — Fetch merged-PR review comments

Run `scripts/fetch_comments.sh` against the target repo. It runs a pipeline of standalone scripts under `scripts/lib/`: list PRs, fetch comments, filter and format and group them, then write the result. Run that script with `--help` for its flags (PR state, PR count cap, concurrency, timeout). Full spec: [references/fetch-plan.md](references/fetch-plan.md).

- The script writes a markdown comment dump to `~/.cache/comments-to-rules/{owner}-{repo}/` by default.
- Use `--output` to choose a different location. Give it a directory to get one chunk file per language. Give it any other path to get one combined file.
- In directory mode, the script groups the dump by language already: `<language>/comments-NNN.md`, 250 comments per chunk. This keeps each `Read` call in Step 2 cheap — see the token-usage note in `PLAN.md`.
- The script drops a comment shorter than 10 characters before you see it (`--min-length` to change this). It measures this on the prose only, with any ` ```suggestion ` block excluded from the count. This is a mechanical filter for pure noise — `lgtm`, `nit`, `+1`, and similar. It does not replace the judgment-based filtering in Step 2.
- A comment with a ` ```suggestion ` block skips that length filter entirely, however short its prose. The suggestion is signal on its own, even with no prose beside it — see Step 2. That comment also gains an `Original code:` block above it: the surrounding code GitHub attached to the comment, showing what the suggestion replaced.
- The script reports its own progress: the repo it detected, the output location, each fetch batch, and each file it writes. Show this progress to the user. Do not run the script silently.
- The default PR limit is 1000, most-recent-first. Pass `--all` for no cap. If the PR count exceeds the default limit, the script exits with status 2 and a `NEEDS_INPUT` message. Ask the user whether to use the most recent 1000 PRs or all of them, then re-run with that choice.
- If the user interrupts the script (Ctrl-C) during a large fetch, the script stops after the batch in progress. It writes what it fetched so far, and it prints the PR range it did not reach. Tell the user this, and offer to resume later for that range.
- If `gh` is missing or not authenticated, or if `jq` or `timeout` is missing, stop and tell the user how to fix it. Do not run `gh auth login` or `gh auth refresh` yourself — see Prerequisites.
- If the repo has no merged PRs, tell the user, then skip to Step 3 (the local-file pass alone).

### Step 2 — Filter and group comments into rules

The dump is already grouped by language: one subdirectory or section per language, from Step 1. It is already filtered by length. Read each language's comments yourself — do not script this part.

- Drop noise the length filter missed: approvals with extra words ("LGTM" plus a comment), bot comments, and discussion with no actionable instruction. This step needs judgment. The length filter does not.
- Keep a comment that states or implies a coding convention — for example, "use `const` not `let` here", "always handle this error", or "prefer an early return".
- When two or more comments state the same rule, merge them into one rule.
- A comment with a ` ```suggestion ` block, and an `Original code:` block above it, holds a real before/after pair from this repo's own history. Read the diff, not only the prose beside it — the diff can state a rule on its own, even where the prose says little or nothing. A suggestion that turns an `if`/`else` into a guard clause and a return states "prefer an early return" by itself, with or without a comment that says so. When you keep a rule this way, treat the diff as the source, not just as an example for a separately-stated rule.
- Where a rule does earn a code example, see `rule-template.md` for when one is worth adding. Prefer a real `Original code:` and `suggestion` pair over a fabricated one — it is a genuine `notLikeThis`/`ratherLikeThis` pair already.

A language can have too few actionable comments to support a rule with confidence. As a rough guide, treat fewer than three surviving rules as too few. This can happen with thin PR history, a small or new repo, or a language reviewers rarely touch. In this case, do not force a rule file out of what little exists. Note which languages are thin. Keep the few rules that did survive. Let Step 3 write the rest of that language's file. This includes the extreme case: a language with zero surviving comments still gets a file, written entirely by Step 3.

Before you write a language's rule file, check the target repo's `.claude/rules/` directory for any existing file that already covers this language. Do not check only for an exact `code-style-{language}.md` name — read every existing file's `paths:` frontmatter and compare it against this language's file extensions.

- If an existing file's `paths:` already covers this language, ask the user (with `AskUserQuestion`): update that file, or create a new `code-style-{language}.md` beside it? Ask this once per language with a match, not once per file.
- If you update an existing file, read it first. Merge in your new findings. Keep existing rules that still hold. If a new finding contradicts an existing rule, stop and ask the user which one to keep — never overwrite silently.
- If no existing file covers this language, create `.claude/rules/code-style-{language}.md`.

Either way, follow the structure in [references/rule-template.md](references/rule-template.md): a `paths:` frontmatter glob, an optional context note, and rule bullets. State a rule in prose and stop there by default — add a code-fenced good/bad example only when the rule would stay unclear without one. Where a real PR comment gives a clean example that a rule genuinely needs, quote it verbatim rather than paraphrasing it. Write every rule file in ASD-STE100 compliant prose. Invoke the `asd-ste100` skill for this pass, if it is installed. If it is not installed, note in the file that you skipped this check.

### Step 3 — Local-file pass

Scan the target repo's files, respecting `.gitignore`, grouped by language. Scan every language present in the codebase, not only the ones Step 2 already covered. Infer conventions from the code itself: naming style, import order, formatting, test structure, error handling, and similar patterns.

- For a language Step 2 already covered well, add these findings under a "Locally Inferred" heading. Keep this section visually separate from the PR-comment rules above it, so the source of each rule stays clear.
- For a language Step 2 flagged as thin, or skipped, this pass is the language's primary source — not a bonus. This covers a language with zero PR comments, and a repo with no merged PRs at all (see Step 1). Write the file from local inference alone. State this plainly in the file's context note — see `rule-template.md` — for example: "These rules come from local code conventions. PR review history for this language was too thin to draw rules from." Do not label these rules as PR-derived. Do not present a local finding as if a reviewer had said it.
- Where local code follows no consistent convention, do not invent a rule. Add the question to an "Open Questions" section instead — see `rule-template.md` — and ask the user which convention to adopt.
- Do not write a rule file for a language with no actionable rule to state — not from Step 2, not from this step. A rule file whose only content would explain why it has nothing to say is not a rule file. This comes up most often for a language a formatter fully controls, with no PR history and no hand-written convention to infer — for example, JSON files that are only config or lock files, formatted by Prettier alone. In that case, skip the file, and list the language, with a one-line reason, in Step 4's summary instead.

If Step 1 found no merged PRs at all, every language's rule file comes from this step alone. Treat this as the normal path for a new or lightly-reviewed repo, not as a fallback.

**Delegating a language's Step 2 and Step 3 work to a subagent is a reasonable choice on a repo with several languages.** Each language then gets its own separate context to read comments and scan files in. If you do this, tell the subagent what its final report must include:

- The language, and the file path it wrote or updated.
- The total rule count.
- How many comments it used to create rules — one running tally, updated each time it keeps or drops a comment. Do not have it reconstruct this count afterward by rereading the file.

Step 4 builds its summary from these reported numbers alone. Do not reread a finished rule file to count its rules or confirm its content. The subagent that wrote the file already knows both numbers.

### Step 4 — Confirm the rule files are complete

Before you offer anything further, tell the user plainly that rule-file writing is done. This is a separate event from the review offer in Step 5, not a lead-in to it. State it as its own message, with a summary that covers:

- **Files.** Every `.claude/rules/code-style-{language}.md` you wrote or updated this run.
- **Languages covered.** The distinct languages across those files.
- **PRs fetched.** The PR count from Step 1's own printed output. Read this number — do not recount it yourself.
- **Comments fetched.** The total comment count from Step 1's own printed output — the count after the length filter, before the semantic filter. Read the script's "wrote N comment(s) across M language group(s)" line. Do not derive this by reading the comment dump.
- **Comments used.** How many comments survived Step 2's semantic filter and shaped a rule. This number is smaller than "comments fetched" — most fetched comments turn out to be noise, discussion, or a duplicate of a rule you already captured. Get this from the running tally you kept per language while filtering — see Step 3's note on delegating to a subagent. Do not get it by rereading a finished rule file and counting.
- **Rules created.** The total rule count across every file you wrote this run, PR-derived and locally-inferred combined. Sum this from your own tracked count per language, or from each subagent's reported count. Apply the same rule as "Comments used": count while you work, and never recount by rereading the file.
- **Tokens used.** State this as an estimate, and say so. You have no reliable way to read your own exact token usage mid-session. Base the estimate on a rough proxy: divide the character count you read from the comment dump and local files, plus the character count you wrote to rule files, by about 4. Tell the user this is a rough estimate, not a billed figure, and point them to `/cost` for an exact number.
- **Languages skipped.** Any language Step 3 chose not to write a file for — no actionable rule from either step, or too few files in the repo to be worth a dedicated file — with a one-line reason each.

Example:

> Rule files complete.
>
> - Wrote `.claude/rules/code-style-python.md`, updated `.claude/rules/code-style-shell.md` (2 files)
> - Languages: python, shell
> - 342 merged PRs fetched, 118 comments survived filtering, 23 of those used to create rules
> - 19 rules created total
> - ~28K tokens used this run (rough estimate — run `/cost` for an exact figure)
> - Skipped json — only config and lock files, formatting fully enforced by Prettier, nothing to hand-document

If Step 3 left any open questions unresolved, list them here too, separate from the summary.

### Step 5 — Offer next steps

Only after Step 4's completion message, ask the user (with `AskUserQuestion`, single-select) what to do next:

- **View the rules in detail.** Walk through each rule file's content with the user in chat — read it, then summarize or discuss it. This option needs no repo scan.
- **Run a review of the codebase using these rules.** Read the rule files and the repo's files. Write every violation you find to `CODE_RULE_VIOLATIONS.md`, in the target repo's root, grouped by file, then by rule. Overwrite any existing file of that name from a prior run. Tell the user you wrote the file, with a one-line count — for example, "14 violations across 6 files — see `CODE_RULE_VIOLATIONS.md`". Do not also paste the full violation list into the chat.
- **Neither — I'm done.** Stop. Leave the rule files in place for later use.

## Files

- `scripts/fetch_comments.sh` — the entrypoint. It orchestrates `scripts/lib/` to fetch merged-PR review comments and write the markdown dump.
- `scripts/lib/list_prs.sh`, `fetch_pr_comments.sh`, `format_comments.sh`, `write_output.sh` — the pipeline stages. Each one runs on its own too (`--help` on any of them). The entrypoint sources them and calls them in sequence.
- `references/rule-template.md` — the output format for `.claude/rules/code-style-{language}.md` files.
- `references/fetch-plan.md` — the detailed spec for the fetch pipeline: batching, concurrency, timeout and interrupt handling, filtering, and language grouping. Keep it in sync with the scripts.
