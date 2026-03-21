# ralph-loop-fixed

A fork of the official [ralph-loop](https://github.com/anthropics/claude-plugins-official/tree/main/ralph-loop) Claude Code plugin that fixes the `$ARGUMENTS` shell expansion vulnerability.

## What's Fixed

The official plugin passes user-typed text (`$ARGUMENTS`) directly through shell expansion in a `` ```! `` bash block. Any shell-meaningful character in the user's prompt breaks the plugin:

- Newlines (multi-line prompts)
- Quotes (`"`, `'`)
- Parentheses (`(`, `)`)
- Angle brackets (`<`, `>`)
- Glob characters (`*`, `?`, `[`, `]`)
- Commas, semicolons, pipes

This affects 6+ open issues on the official repo: [#128](https://github.com/anthropics/claude-plugins-official/issues/128), [#136](https://github.com/anthropics/claude-plugins-official/issues/136), [#145](https://github.com/anthropics/claude-plugins-official/issues/145), [#610](https://github.com/anthropics/claude-plugins-official/issues/610), [#748](https://github.com/anthropics/claude-plugins-official/issues/748), and [claude-code#16037](https://github.com/anthropics/claude-code/issues/16037).

### The Fix

Replace raw `$ARGUMENTS` expansion with a **heredoc using a single-quoted delimiter**:

```bash
# Before (broken):
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" $ARGUMENTS

# After (fixed):
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" --from-stdin <<'RALPH_PROMPT_EOF'
$ARGUMENTS
RALPH_PROMPT_EOF
```

Single-quoted heredoc delimiters (`'RALPH_PROMPT_EOF'`) prevent all shell expansion. The user's text passes through as literal stdin, never touching the shell parser. The setup script reads and parses the input from stdin.

## What Else Changed

- **commands/ to skills/**: Migrated from the legacy `commands/` pattern to modern `skills/` pattern
- **--from-stdin**: Setup script gained `--from-stdin` flag to read prompt + flags from stdin
- **Everything else is identical** to the official plugin: stop hook, cancel-ralph, help, state file format

## Installation

1. Add this repo as a marketplace in Claude Code settings (`~/.claude/settings.json`):

```json
{
  "extraKnownMarketplaces": {
    "dansunotori": {
      "source": {
        "source": "git",
        "url": "https://github.com/dansunotori/ralph-loop-fixed.git"
      }
    }
  }
}
```

2. Disable the official plugin and install this one:

```json
{
  "enabledPlugins": {
    "ralph-loop@claude-plugins-official": false
  }
}
```

Then run `/plugin install ralph-loop-fixed@dansunotori`.

## Usage

Same as the official plugin:

```
/ralph-loop Build a REST API for todos --max-iterations 20
/ralph-loop Fix the auth bug --completion-promise "FIXED" --max-iterations 10
/cancel-ralph
/ralph-help
```

## Investigation

Full root cause analysis: see `docs/migration-audit/ralph-loop-investigation.md` in the [samexpert-astro](https://github.com/nicholasgriffintn/samexpert-astro) repo (where this investigation was conducted).
