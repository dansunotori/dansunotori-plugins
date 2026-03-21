# Ralph Loop Plugin Fork — Design

## Problem

The official `ralph-loop` plugin (`claude-plugins-official`) passes `$ARGUMENTS` through shell expansion in a `` ```! `` bash block. `$ARGUMENTS` contains arbitrary user-typed text. Any shell-meaningful character breaks the plugin: newlines, quotes, parentheses, angle brackets, globs, commas. This is documented in 6+ open issues (#128, #136, #145, #610, #748 on the plugin repo; #16037 on claude-code repo). None are resolved.

## Solution

Replace raw `$ARGUMENTS` shell expansion with a **heredoc** using a single-quoted delimiter. Empirically verified: Tengu's security checks pass heredocs with multi-line content containing all shell metacharacters.

### Core fix

**Before (broken):**
```markdown
```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" $ARGUMENTS
```
```

**After (fixed):**
```markdown
```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" --from-stdin <<'RALPH_PROMPT_EOF'
$ARGUMENTS
RALPH_PROMPT_EOF
```
```

The single-quoted heredoc delimiter (`'RALPH_PROMPT_EOF'`) prevents all shell expansion. The script reads prompt + flags from stdin instead of positional args.

### Script changes (`setup-ralph-loop.sh`)

Add `--from-stdin` as first argument:
- When present, read all stdin content
- Split into words and run the existing flag-parsing loop
- Non-flag words become PROMPT_PARTS (identical to current positional-arg behaviour)
- Keep existing positional-arg parsing as fallback for direct script invocation

### Plugin structure (commands → skills)

Convert all three slash commands to skills (modern plugin pattern):

```
ralph-loop-fixed/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── ralph-loop/
│       └── SKILL.md
│   └── cancel-ralph/
│       └── SKILL.md
│   └── help/
│       └── SKILL.md
├── hooks/
│   └── hooks.json
│   └── stop-hook.sh
├── scripts/
│   └── setup-ralph-loop.sh
└── README.md
```

SKILL.md frontmatter mapping:
- `description:` — preserved
- `name:` — added (required for slash command registration in skills)
- `allowed-tools:` — preserved
- `argument-hint:` — preserved
- `disable-model-invocation: true` — replaces `hide-from-slash-command-tool`

### What stays the same

- Stop hook (`stop-hook.sh`) — unchanged
- Hooks configuration (`hooks.json`) — unchanged
- Cancel-ralph logic — unchanged
- Help content — unchanged
- Plugin metadata (`plugin.json`) — name/description updated

### Edge case

If the user's prompt contains `RALPH_PROMPT_EOF` on its own line, the heredoc terminates early. This is extremely unlikely for natural language prompts.

## Installation

1. Create git repo at `~/Projects/ralph-loop-fixed/`
2. Push to GitHub
3. Add as local marketplace in `~/.claude/settings.json` → `extraKnownMarketplaces`
4. Install via `/plugin install ralph-loop-fixed@<marketplace-name>`
5. Disable `ralph-loop@claude-plugins-official` in `enabledPlugins`

## Testing checklist

1. Single-line prompt → loop starts
2. Multi-line prompt → loop starts
3. Prompt with `"quotes"`, `(parens)`, `<brackets>`, `I'm`, commas → loop starts
4. `--max-iterations N` → parses correctly
5. `--completion-promise "TEXT"` → parses correctly
6. `/cancel-ralph` → stops loop
7. Stop hook → feeds prompt back between iterations
8. Iteration counter increments
9. Max iterations respected
10. Completion promise detection works

## Upstream PR

After local testing passes all checks, submit PR to `anthropics/claude-plugins-official` with:
- The heredoc fix for $ARGUMENTS shell expansion
- commands/ → skills/ migration
- --from-stdin support in setup script
- References to issues #128, #136, #145, #610, #748

## Evidence

Investigation report: `docs/migration-audit/ralph-loop-investigation.md`
Heredoc empirical test: passed with multi-line input + quotes + parens + angle brackets (2026-03-21)
