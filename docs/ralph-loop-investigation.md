# Ralph Loop ```! Block Failure — Root Cause Investigation

## The Errors

Two distinct error messages observed for multi-line `$ARGUMENTS`, depending on content:

**Error A** (original — no shell-special chars in args):
```
Error: Bash command permission check failed for pattern "```!
"/path/to/setup-ralph-loop.sh" LOAD THE SKILL...
perform audit number 2...
```": Command contains newlines that could separate multiple commands
```

**Error B** (when args contain shell quote chars like apostrophe in `I'm`):
```
Error: Bash command permission check failed for pattern "```!
"/path/to/setup-ralph-loop.sh" say "hello world".
I'm serious, just do it
--max-iterations 2
```": This Bash command contains multiple operations. The following parts require approval: I 'm serious, just do it, --max-iterations 2
```

Both come from Claude Code's built-in permission system (Tengu). Different checks in the pipeline fire depending on how the content interacts with shell parsing.

## Empirical Test Results

| Input type | Result | Error |
|-|-|-|
| Single-line | PASS — loop starts normally | None |
| Multi-line (no quotes in args) | FAIL | Error A: Tengu WGT newline check |
| Multi-line (apostrophe in args) | FAIL | Error B: multi-operation permission resolver |

**Tested 2026-03-21** on Claude Code v2.1.79, VSCode extension.

## What Is NOT the Cause

| Suspect | Verdict | Evidence |
|-|-|-|
| Stop hook (`stop-hook.sh`) | NOT involved | Stop hook only fires on `Stop` events. This error occurs during skill command loading. Verified 5+ times across sessions. |
| `no-chained-commands.sh` hook | NOT involved | The `` ```! `` block is pre-processed before any tool call. Our hook never fires. It would only matter if the `` ```! `` wrapper were removed entirely. |
| Issue #136 (allowed-tools quote mismatch) | NOT a problem in v2.1.79 | Single-line test passed — Claude Code's pattern matcher handles quotes around paths correctly. |

## The Root Cause

**`$ARGUMENTS` substitution preserves newlines from user input. When these newlines end up inside a `` ```! `` bash execution block, Claude Code's built-in permission system rejects the resulting multi-line command.**

### The Processing Chain

```
1. User types: /ralph-loop <multi-line arguments> --max-iterations N
2. Skill tool loads commands/ralph-loop.md
3. $ARGUMENTS substituted with user's text (PRESERVING NEWLINES)
4. The template:
   ```!
   "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" $ARGUMENTS
   ```
   becomes:
   ```!
   "/full/path/to/setup-ralph-loop.sh" line one of prompt
   line two of prompt
   --max-iterations N
   ```
5. Function Wg (Claude Code engine) processes the ```! block:
   - Regex WNK extracts content between fences -> O[1]
   - A = O[1].trim() -> command WITH newlines from $ARGUMENTS
   - Calls fY(Bash, {command: A}, ...) for permission check
6. fY runs built-in Tengu security checks:
   - WGT (newline check) may fire -> Error A
   - Multi-operation resolver may fire -> Error B
   - Which fires depends on how shell quote parsing interacts with content
7. behavior !== "allow" -> Wg throws error
8. Error message includes O[0] (full match with ```! markers) for display context
```

### Why the backticks appear in the error

The `Wg` function uses `O[0]` (the full regex match INCLUDING `` ```! `` and `` ``` `` fence markers) in the error display: `new hu('Bash command permission check failed for pattern "${O[0]}": ${H.message}')`. The fences are NOT part of what Tengu checks — they are display context only.

## The Blockers

The `` ```! `` block is pre-processed by Claude Code's engine (function `Wg`) before any tool call happens. The command never reaches PreToolUse hooks — it's checked and rejected entirely within `Wg` → `fY` → Tengu.

| Blocker | Source | Error message | Fires when |
|-|-|-|-|
| Tengu WGT | Claude Code built-in | "Command contains newlines that could separate multiple commands" | Newline followed by non-whitespace in `fullyUnquotedPreStrip` |
| Multi-op resolver | Claude Code built-in | "This Bash command contains multiple operations..." | Command split into lines produces parts not matching allowed-tools |

Which of the two fires depends on how shell quote parsing interacts with the content (e.g. apostrophes in `I'm` change the parsing path).

**Our `no-chained-commands.sh` hook is NOT involved.** It would only matter if the `` ```! `` wrapper were removed (lines 12/14 of ralph-loop.md) and Claude executed the command via the Bash tool directly.

### Tengu WGT (deminified from binary)

```javascript
function WGT(_) {
  let { fullyUnquotedPreStrip: T } = _;
  if (!/[\n\r]/.test(T))
    return { behavior: "passthrough", message: "No newlines" };
  if (/(?<![\s]\\)[\n\r]\s*\S/.test(T))
    return F("tengu_bash_security_check_triggered", { checkId: wK.NEWLINES, subId: 1 }),
      { behavior: "ask", message: "Command contains newlines that could separate multiple commands" };
  return { behavior: "passthrough", message: "Newlines appear to be within data" }
}
```

### Multi-operation resolver (error template from binary)

```javascript
`multiple operations. The following part${R.length>1?"s":""} require${R.length>1?"":"s"} approval: ${R.join(", ")}`
```

Where `R` is an array of command lines that don't match any allowed-tools pattern.

## Known Issues on GitHub

This is not an isolated problem. It's a known, widespread, unfixed issue class affecting Anthropic's own official plugin. The fundamental design flaw: `$ARGUMENTS` (user-typed natural language) is passed through shell expansion in a `` ```! `` block.

| Issue | Repo | Date | Problem |
|-|-|-|-|
| #128 | plugins-official | 2026-01-06 | Same bug: multi-line `$ARGUMENTS` → "Command contains newlines" |
| #136 | plugins-official | 2026-01-06 | `allowed-tools` pattern doesn't match quoted command path |
| #145 | plugins-official | 2026-01-07 | Commas/periods in prompt parsed as separate operations. No workaround. |
| #610 | plugins-official | 2026-03-12 | `$ARGUMENTS` unquoted → zsh glob expansion breaks on `[ ]`, `*`, `?` |
| #748 | plugins-official | 2026-03-19 | Shell metacharacters `(`, `)`, `'` in prompt cause parse errors |
| #16037 | claude-code | 2026-01-02 | Same newline bug filed against Claude Code itself |

Comment on #128: even single-line input with `<promise>COMPLETE</promise>` gets rejected — `<` and `>` are shell redirection operators.

**The newline issue is just one symptom.** Any shell-meaningful character in the user's prompt breaks the plugin: newlines, quotes, parentheses, angle brackets, globs, commas. The root problem is passing unescaped user text through shell expansion.

## The Actual Fix

### The real fix: don't pass user text through the shell

The `$ARGUMENTS` variable contains arbitrary user-typed natural language. Passing it through shell expansion is fundamentally unsafe — not just for newlines, but for ALL shell-meaningful characters. Proposed in issue #426 and #748:

**Option A — Environment variable (proposed in #748):**
```markdown
```!
RALPH_ARGS="$ARGUMENTS" "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh"
```
```
The script reads `$RALPH_ARGS` instead of positional args. This avoids shell expansion of the prompt entirely.

**Option B — Temp file / stdin (proposed in #426):**
Write `$ARGUMENTS` to a temp file, pass the file path to the script. The script reads the prompt from the file. Zero shell expansion risk.

**Option C — Claude Code engine fix:**
The `$ARGUMENTS` substitution in `Wg` (the `` ```! `` processor) should shell-escape the value before embedding it in the command string. Or better: pass it as a separate parameter that bypasses shell parsing.

### Partial fix: collapse newlines in `Wg`

If only the newline issue needs to be addressed (not the broader shell metacharacter problem), the `Wg` function could collapse newlines:

```javascript
// Current:
let A = O[1]?.trim();

// Partial fix (newlines only):
let A = O[1]?.trim().replace(/[\n\r]+/g, ' ');
```

This fixes the specific "Command contains newlines" error but does NOT fix issues #145, #610, #748 (commas, globs, metacharacters).

### Workaround (user-side, no code changes)

Keep `/ralph-loop` prompt on a single line. Avoid shell-meaningful characters: `( ) ' " < > [ ] * ? { } , ; | & !`. This is fragile — natural language routinely contains these characters.

## Evidence Files

- `/tmp/test-tengu-regex.mjs` — Reproduces the Tengu WGT regex match against our exact case
- `/tmp/test-scenarios.mjs` — Full simulation of all input scenarios against all checks
- `/tmp/analysis-wg-function.md` — Deminified analysis of the Wg function
