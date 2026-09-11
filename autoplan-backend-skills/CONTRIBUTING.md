# Contributing

## The bar for adding a pattern

A pattern belongs here if it is **already working in one of our repos** and a developer starting
the next integration would otherwise have to rediscover it. Cite the source: repo, file, and what
it solves. Aspirational best practice with no implementation behind it does not go in — that is
what the Microsoft `azure-*` skills are for.

When two repos disagree, document the winner and say why. Echoes is the default reference.

## Writing a skill

```
skills/<skill-name>/
  SKILL.md
  references/*.md
  references/templates/*
```

`SKILL.md` needs YAML frontmatter:

```yaml
---
name: autoplan-example
description: "One line on what it does. WHEN: \"trigger phrase\", \"another phrase\"."
---
```

The `description` is the only thing Copilot sees when deciding whether to activate the skill, so
the `WHEN:` list should use the words a developer would actually type.

Keep `SKILL.md` under roughly 150 lines. It is loaded in full on every activation; `references/`
files are only read when needed. Push detail, long code and rationale into `references/`.

Prefer linking a template file over inlining a large code block.

## Definition of done

A skill is finished when it can **regenerate the corresponding part of EchoesIntegration from
scratch**. If it cannot, it is still a description rather than a skill.

Also check:

- [ ] Every non-obvious claim cites a repo and file
- [ ] Every claim was verified by opening the file, not from a grep hit
- [ ] `WHEN:` triggers use realistic phrasing
- [ ] Templates compile / are valid for their file type
- [ ] No secrets, tokens, connection strings or customer data — including in examples
- [ ] Placeholders are obvious (`<Integration>`, `https://api.example.com`)
- [ ] All relative links resolve

Verify links before pushing:

```powershell
Get-ChildItem skills, docs -Recurse -Filter *.md | ForEach-Object {
  $dir = $_.DirectoryName
  [regex]::Matches((Get-Content $_.FullName -Raw), '\]\(([^)]+)\)') | ForEach-Object {
    $t = $_.Groups[1].Value -replace '#.*$',''
    if ($t -and $t -notmatch '^(https?:|mailto:)' -and -not (Test-Path (Join-Path $dir ($t -replace '/','\')))) {
      "BROKEN: $t"
    }
  }
}
```

## Scripts must be ASCII

`scripts/*.ps1` are **ASCII only** — no em-dashes, curly quotes or other typography. Windows
PowerShell 5.1 reads a BOM-less UTF-8 script as ANSI, which turns a single em-dash into three
mojibake characters and can break parsing outright. Markdown is exempt; only the scripts matter.

Check before committing:

```powershell
Get-ChildItem scripts -Filter *.ps1 | ForEach-Object {
  $t = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($_.FullName))
  $n = ([regex]::Matches($t, '[^\x00-\x7F]')).Count
  $errs = $null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errs) | Out-Null
  "{0}: nonAscii={1} parseErrors={2}" -f $_.Name, $n, @($errs).Count
}
```

Both counts must be zero.

## Changing a shared skill

These are shared, so a change lands for everyone at once. Open a PR. For anything that alters an
existing convention (rather than documenting a new one), get agreement first — the point of the
repo is that we stop diverging.

## Testing a change locally

`Install-Skills.ps1` symlinks by default, so an edit is live immediately. If it fell back to
copying (no symlink permission), re-run the script — it recognises its own copies and refreshes
them without `-Force`. A skill folder it did not install is left alone until you pass `-Force`.

Then start a fresh Copilot session — skills are read at startup.
