# Rule File Template

This is the format for every `.claude/rules/code-style-{language}.md` file
this skill writes into a target repo. It matches the structure already set
by this repo's own example files: `.claude/rules/code-style-shell.md` and
`.claude/rules/code-style-markdown.md`. Read those two for a full worked
example of the structure. Match their density of code examples less
closely — they predate the "examples are the exception" guidance below,
so they carry more examples than a new rule file should.

## Structure

````markdown
---
paths:
  - "**/*.ext"
  - "**/*.alt-ext"
---

# {Language} Rules

{Optional context note — see "Context note" below.}

- {Rule 1, a short imperative instruction. Most rules stop here — no example.}
- {Rule 2.}
- {Rule 3, a rule that reads two ways without a contrast, so it earns one:}

```
{notLikeThis example.}
```

```
{ratherLikeThis example.}
```

## Locally Inferred

{Section added by SKILL.md Step 3. Same bullet style. Kept separate from
the PR-comment-derived rules above so provenance stays clear.}
````

## Parts

- **Frontmatter `paths:`.** A YAML list of glob patterns for the files this
  rule set applies to. Cover every extension the language groups under. The
  fetch pipeline's language map, in `scripts/lib/format_comments.sh`,
  already groups related extensions this way — for example, `sh`, `bash`,
  and `zsh` under one `shell` language. Mirror that grouping here. Do not
  write one rule file per extension.
- **H1.** `# {Language} Rules`, matching the file's language.
- **Context note (optional).** A short paragraph under the H1, for either of
  two cases:
  - The rule set is a going-forward convention, not a retrofit mandate. This
    applies when the PR comments it draws from only reflect newer code, and
    older code in the repo does not consistently follow it yet. State this
    plainly — see `code-style-shell.md`'s opening paragraph for the pattern.
    This stops a reader, human or agent, from rewriting working legacy code
    just to satisfy a rule that was never meant to apply retroactively.
  - The file, or most of it, comes from Step 3's local-code inference rather
    than PR comments, because PR review history for this language was too
    thin or entirely absent — see `SKILL.md` Step 3. State this plainly, for
    example: "These rules come from local code conventions. PR review
    history for this language was too thin to draw rules from." Do not
    present a locally-inferred rule as if a reviewer had said it.
- **Rule bullets.** One short imperative instruction per bullet. Where a
  real PR comment gives a clean, concrete example, quote it, or the code it
  commented on, verbatim, rather than paraphrasing it. This keeps the rule
  traceable to something that actually happened in this repo.
- **Good/bad code examples — the exception, not the default.** A rule
  states its instruction in prose and stops there. Add a `notLikeThis` and
  `ratherLikeThis` pair of contrasting fenced blocks only when the prose
  alone would leave the reader unsure what to do — a rule about layout or
  punctuation that words cannot show as clearly as code, or a case where a
  plausible-looking alternative needs to be ruled out by name. Do not add
  an example to illustrate a rule that is already unambiguous in prose. A
  rule file with ten rules and two examples is normal. A rule file with an
  example under every bullet means most of those examples were not needed.
- **`## Locally Inferred` section.** Step 3 of `SKILL.md` adds this, after
  the PR-comment-derived rules above it. Never interleave the two kinds of
  rule. Use the same bullet style. Omit the whole section if Step 3 found
  nothing to add for this language. Use this heading only when the file
  already has PR-comment-derived rules above it to separate from. When Step
  3 is the file's only source — PR history was too thin or absent for this
  language — write its findings as plain top-level rule bullets instead.
  There is nothing to separate them from, and a lone "Locally Inferred"
  heading over the entire file would only add noise. In that case, the
  context note marks the file's origin, not this heading.
- **`## Open Questions` section (optional).** Step 3 adds this when local
  code follows no consistent convention. Do not invent a rule in that case.
  List the convention, and a one-line summary of what you found, so the
  agent can ask the user which one to adopt, rather than guess. Drop the
  bullet once the user answers, and a rule — or a decision to add none —
  replaces it.

## Writing style

All prose in a generated rule file — the context note, the rule bullets,
everything except code fences — must be ASD-STE100 compliant. See the
`asd-ste100` skill. Use short sentences. Use active voice. Write one
instruction per sentence. Do not use phrasal verbs. Do not use semicolons.
