# notchwow Markdown Syntax for AI Agents

This document describes the Markdown dialect that notchwow expects AI agents to write inside the Markdown workspace.

## Storage Location

- Markdown notes live under the configured Markdown working directory. By default this is `~/keyoti/mds/`.
- Attachments live under the `attachments/` child directory of the same Markdown root.
- Notes are plain UTF-8 `.md` or `.markdown` files.

## Note Titles

- Prefer a single first-level heading on the first line:

```markdown
# Project Plan
```

- notchwow uses the first `# ` heading as the note title.
- When a note is edited, notchwow may rename the file from the first heading. Use filesystem-safe titles and keep note titles unique.

## Wiki Links Between Notes

Use Obsidian-style double-bracket links for note-to-note navigation:

```markdown
See [[Project Plan]] for the current roadmap.
```

notchwow resolves a wiki link against existing notes by:

- first `# ` heading, for example `[[Project Plan]]`
- file stem, for example `[[Project Plan]]` for `Project Plan.md`
- filename, for example `[[Project Plan.md]]`
- path relative to the Markdown root, for example `[[areas/Project Plan]]` or `[[areas/Project Plan.md]]`

Resolution is case-insensitive and ignores diacritics. If multiple notes share the same title or filename stem, the first loaded match wins, so agents should avoid duplicate note titles.

### Heading And Block Anchors

Agents may write familiar Obsidian-style anchors:

```markdown
[[Project Plan#Milestones]]
[[Project Plan^launch-block]]
```

Current notchwow navigation resolves the note part and opens the target note. It does not scroll to the heading or block anchor yet.

### Unsupported Wiki-Link Forms

Do not use Obsidian alias syntax as public authoring syntax:

```markdown
[[Project Plan|roadmap]]
```

The underlying editor engine reserves `|` inside wiki links for its internal storage form, so agents should write the visible note target directly as `[[Project Plan]]`.

## Standard Markdown

Agents may use normal Markdown:

````markdown
## Section

- Bullet
- [ ] Todo
- [x] Done

**bold**, *italic*, ~~strikethrough~~, `inline code`

> Quote

> [!important]
> Important notes render as callouts.

[External link](https://example.com)

```swift
print("hello")
```
````

GitHub-style pipe tables are supported:

```markdown
| Metric | Value | Trend |
| :----- | ----: | :---: |
| Focus  | 92%   | Up    |
| Bugs   | 3     | Down  |
```

## Math

Inline math:

```markdown
$E = mc^2$
```

Block math:

```markdown
$$
\int_0^1 x^2 dx = \frac{1}{3}
$$
```

## Attachments And Images

Use wiki-style embeds for local attachments:

```markdown
![[attachments/diagram.png]]
```

When users paste images or files, notchwow copies them into the Markdown root's `attachments/` directory and inserts the appropriate reference.

## Agent Writing Rules

- Prefer `[[Exact Note Title]]` for note links.
- Keep note titles unique and stable.
- Do not invent links to missing notes unless the task explicitly asks to create those notes.
- Use relative attachment paths under `attachments/`.
- Do not edit files under `attachments/manifest.json` by hand unless implementing attachment storage behavior.
