---
paths:
  - "*/**/*.md"
---

# Markdown Rules

- Write prose in Simplified Technical English (ASD-STE100), STE-flavored mode. Use the `asd-ste100` skill. Use active voice. Use one instruction per sentence. Do not use semicolons or phrasal verbs. Keep sentences short. If the `asd-ste100` skill is not installed, suggest that the user install it.
- Run prettier on a markdown file when you finish making changes.
- Use ATX headings (`#`) only. Never use Setext underlines.
- Include exactly one H1 per file. Match the H1 to the document or section title.
- Use Title Case for H1 and H2 headings. Sentence-style phrasing is fine for lower-level headings.
- Wrap file paths, commands, package names, identifiers, and config values in backticks. Do not use bold text or plain text for these.
- Reserve bold text for a key phrase or a warning inside a sentence. Do not use bold text to label paths or commands.
- Use `-` for all bullet lists. Never use `*`.
- Tag each fenced code block with a language, for example ` ```bash ` or ` ```yaml `, whenever you know the language.
- Use tables for reference or parameter data, such as units, fields, and object dictionaries. Left-align table columns by default.
- Write relative markdown links with descriptive link text, for example `[Descriptive Name](relative/path.md)`. Do not write bare paths.
- Add a `## See also` section at the end of a doc that has closely related docs. Link each related doc by its relative path.
- Reference diagrams with `![alt text](path/to/diagram.svg)`. Do not use raw `<img>` tags.
- Do not hard-wrap prose. Write long lines and let prettier format the file.
