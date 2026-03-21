# Ralph Loop Plugin Fork — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fork the official ralph-loop plugin to fix `$ARGUMENTS` shell expansion using heredoc, convert commands/ to skills/, and prepare for upstream PR.

**Architecture:** Single-quoted heredoc in the `` ```! `` block pipes `$ARGUMENTS` to the setup script via stdin, bypassing shell expansion entirely. The script gains `--from-stdin` support to parse flags and prompt from stdin. All slash commands migrate from `commands/*.md` to `skills/*/SKILL.md`.

**Tech Stack:** Bash, Claude Code plugin framework (skills, hooks)

---

### Task 1: Create plugin directory structure

**Files:**
- Create: `~/Projects/ralph-loop-fixed/.claude-plugin/plugin.json`

**Step 1: Create directories**

Run: `mkdir -p ~/Projects/ralph-loop-fixed/.claude-plugin`
Run: `mkdir -p ~/Projects/ralph-loop-fixed/skills/ralph-loop`
Run: `mkdir -p ~/Projects/ralph-loop-fixed/skills/cancel-ralph`
Run: `mkdir -p ~/Projects/ralph-loop-fixed/skills/help`
Run: `mkdir -p ~/Projects/ralph-loop-fixed/hooks`
Run: `mkdir -p ~/Projects/ralph-loop-fixed/scripts`

**Step 2: Create plugin.json**

Write `~/Projects/ralph-loop-fixed/.claude-plugin/plugin.json`:
```json
{
  "name": "ralph-loop-fixed",
  "description": "Fixed Ralph Loop plugin. Continuous self-referential AI loops for iterative development. Uses heredoc to safely pass user prompts without shell expansion issues.",
  "author": {
    "name": "SAMexpert (fork of Anthropic's ralph-loop)",
    "email": "support@samexpert.com"
  }
}
```

**Step 3: Init git repo**

Run (from `~/Projects/ralph-loop-fixed`): `git init`

---

### Task 2: Create setup-ralph-loop.sh with --from-stdin support

**Files:**
- Create: `~/Projects/ralph-loop-fixed/scripts/setup-ralph-loop.sh`

**Step 1: Write the modified script**

Copy the original script from `~/.claude/plugins/cache/claude-plugins-official/ralph-loop/61c0597779bd/scripts/setup-ralph-loop.sh` and add `--from-stdin` handling.

The key change: insert a `--from-stdin` check BEFORE the existing `while` loop. When `--from-stdin` is the first argument, read all stdin into a variable, split into words, and set them as positional parameters for the existing parsing loop.

```bash
# Add after "set -euo pipefail" and before the existing parsing:

# Check for --from-stdin mode (used by heredoc-based skill invocation)
if [[ "${1:-}" == "--from-stdin" ]]; then
  shift
  # Read all stdin content
  STDIN_CONTENT=$(cat)
  # Use xargs to split into words (handles quoted strings)
  # Then set as positional parameters for the existing parsing loop
  eval set -- $(echo "$STDIN_CONTENT" | xargs printf "'%s' " 2>/dev/null || echo "$STDIN_CONTENT")
fi
```

Wait — `eval` is dangerous. Simpler approach: read stdin line by line, collect words manually, being careful with the existing parsing loop.

Actually, the simplest safe approach: read stdin into an array using `read -ra`, then set positional params:

```bash
if [[ "${1:-}" == "--from-stdin" ]]; then
  shift
  STDIN_CONTENT=$(cat)
  # Split on whitespace into array (same as shell word splitting for positional args)
  read -ra STDIN_WORDS <<< "$STDIN_CONTENT"
  set -- "${STDIN_WORDS[@]}"
fi
```

This splits on whitespace (spaces, tabs, newlines), which is exactly what shell word splitting does for positional arguments. The existing `while [[ $# -gt 0 ]]` loop then parses flags and collects prompt words identically.

**Note:** This means multi-line prompts have newlines collapsed to spaces in PROMPT_PARTS. This matches the original behaviour — the original script also joins words with spaces (`PROMPT="${PROMPT_PARTS[*]:-}"`).

**Step 2: Make executable**

Run: `chmod +x ~/Projects/ralph-loop-fixed/scripts/setup-ralph-loop.sh`

**Step 3: Test directly**

Run: `echo "Build a REST API --max-iterations 5" | ~/Projects/ralph-loop-fixed/scripts/setup-ralph-loop.sh --from-stdin`

Expected: Setup output showing "Max iterations: 5" and prompt "Build a REST API".

Run: `echo "test" | ~/Projects/ralph-loop-fixed/scripts/setup-ralph-loop.sh --from-stdin`

Expected: Setup output showing prompt "test".

Then clean up: `rm .claude/ralph-loop.local.md`

---

### Task 3: Create ralph-loop SKILL.md (the core fix)

**Files:**
- Create: `~/Projects/ralph-loop-fixed/skills/ralph-loop/SKILL.md`

**Step 1: Write the skill**

```markdown
---
name: ralph-loop
description: "Start Ralph Loop in current session"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh:*)"]
disable-model-invocation: true
---

# Ralph Loop Command

Execute the setup script to initialize the Ralph loop:

` ` `!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" --from-stdin <<'RALPH_PROMPT_EOF'
$ARGUMENTS
RALPH_PROMPT_EOF
` ` `

Please work on the task. When you try to exit, the Ralph loop will feed the SAME PROMPT back to you for the next iteration. You'll see your previous work in files and git history, allowing you to iterate and improve.

CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop, even if you think you're stuck or should exit for other reasons. The loop is designed to continue until genuine completion.
```

(Note: the ` ` ` in the plan represents actual backtick-triples — they cannot be nested in this document.)

---

### Task 4: Create cancel-ralph SKILL.md

**Files:**
- Create: `~/Projects/ralph-loop-fixed/skills/cancel-ralph/SKILL.md`

**Step 1: Write the skill**

Port from `commands/cancel-ralph.md`. Change frontmatter: add `name: cancel-ralph`, replace `hide-from-slash-command-tool` with `disable-model-invocation: true`. Body content unchanged.

---

### Task 5: Create help SKILL.md

**Files:**
- Create: `~/Projects/ralph-loop-fixed/skills/help/SKILL.md`

**Step 1: Write the skill**

Port from `commands/help.md`. Add `name: help` to frontmatter. Body content unchanged.

---

### Task 6: Copy hooks (unchanged)

**Files:**
- Create: `~/Projects/ralph-loop-fixed/hooks/hooks.json`
- Create: `~/Projects/ralph-loop-fixed/hooks/stop-hook.sh`

**Step 1: Copy hooks.json**

Identical to original.

**Step 2: Copy stop-hook.sh**

Identical to original. Make executable: `chmod +x ~/Projects/ralph-loop-fixed/hooks/stop-hook.sh`

---

### Task 7: Create README.md

**Files:**
- Create: `~/Projects/ralph-loop-fixed/README.md`

**Step 1: Write README**

Document: what was fixed, why, how to install, link to investigation report, link to upstream issues.

---

### Task 8: Commit and push

**Step 1: Create .gitignore**

```
.claude/*.local.md
```

**Step 2: Stage and commit**

Run: `git add -A`
Run: `git commit -m "feat: fork ralph-loop with heredoc fix for $ARGUMENTS shell expansion"`

**Step 3: Create GitHub repo and push**

Run: `gh repo create samexpert/ralph-loop-fixed --public --source=. --push`

(Adjust org/name as user prefers.)

---

### Task 9: Install locally

**Step 1: Add as local marketplace**

Edit `~/.claude/settings.json` → `extraKnownMarketplaces`:
```json
"ralph-loop-fixed": {
  "source": {
    "source": "git",
    "url": "https://github.com/samexpert/ralph-loop-fixed.git"
  }
}
```

**Step 2: Disable official plugin**

Edit `~/.claude/settings.json` → `enabledPlugins`:
```json
"ralph-loop@claude-plugins-official": false
```

**Step 3: Install**

Run: `/plugin install ralph-loop-fixed@ralph-loop-fixed`

---

### Task 10: Test — single-line prompt

**Step 1: Run single-line test**

Run: `/ralph-loop test single line --max-iterations 1`

Expected: Loop starts, shows "Max iterations: 1".

**Step 2: Cancel**

Run: `/cancel-ralph`

---

### Task 11: Test — multi-line prompt with shell metacharacters

**Step 1: Run multi-line test**

Type in VSCode chat (multi-line):
```
/ralph-loop say "hello world".
I'm serious, just (do) it <now>
--max-iterations 1
```

Expected: Loop starts, shows "Max iterations: 1".

**Step 2: Cancel**

Run: `/cancel-ralph`

---

### Task 12: Test — completion promise

**Step 1: Run with promise**

Run: `/ralph-loop say hello --completion-promise "DONE" --max-iterations 2`

Expected: Loop starts, shows completion promise "DONE".

**Step 2: Cancel**

Run: `/cancel-ralph`
