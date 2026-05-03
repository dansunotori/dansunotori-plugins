---
name: codex-opinion
description: Use when you want a second opinion from OpenAI Codex on code, architecture, bugs, or implementation decisions. Also use when the user asks to "ask Codex", "get Codex's opinion", or "check with Codex".
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/codex-opinion.sh:*)", "Read", "Write(/tmp/codex-prompt*)"]
---

# Codex Second Opinion

Get a second opinion from OpenAI Codex CLI by running it non-interactively in read-only sandbox mode. Uses a wrapper script that enforces `-s read-only --ephemeral` and only accepts `-o` and `-m` flags.

## How to Use

1. **Build the prompt.** Write it to `/tmp/codex-prompt.txt` using the Write tool. Include:
   - What you want reviewed (file paths, function names, the question)
   - Specific concerns or constraints
   - What kind of feedback you want (security, architecture, correctness, alternatives)

2. **Run the wrapper** via Bash, telling Codex to read the prompt file:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/codex-opinion.sh -o /tmp/codex-opinion.md "Read /tmp/codex-prompt.txt for your full instructions, then follow them."
```

3. **Read the output** from `/tmp/codex-opinion.md`.

4. **Synthesise** Codex's opinion with your own analysis. Present both perspectives to the user — don't just parrot Codex.

**Why use a file for the prompt:** Review prompts routinely contain quotes, backticks, `$()`, code snippets, and other shell metacharacters. Passing them as an inline Bash argument causes shell expansion or argument-breaking. Writing the prompt to a file avoids this entirely. Codex can read files in read-only sandbox mode.

**Why a wrapper script:** The wrapper enforces `-s read-only --ephemeral` and only accepts `-o` and `-m` as additional flags. This prevents accidental or malicious use of dangerous flags like `--dangerously-bypass-approvals-and-sandbox`.

## Wrapper Flags

- `-o FILE` — write Codex's final response to a file (recommended: `/tmp/codex-opinion.md`)
- `-m MODEL` — override the model (default is gpt-5.5)

## Timeouts and Long-Running Reviews

Codex can take 2-5+ minutes for complex reviews. The default Bash timeout is 2 minutes, which will kill the process prematurely.

**For complex prompts**, set the Bash `timeout` parameter to 600000 (10 minutes).

**For very long reviews**, use `run_in_background: true` on the Bash call combined with `-o /tmp/codex-opinion.md`. Read the output file when the background task completes.

## If Codex Fails

- **Timeout:** Set the Bash `timeout` parameter to 600000 (the maximum) and retry.
- **Empty output file:** Codex may have been killed mid-write. Check stderr in the Bash output for clues, then retry.
- **Rate limit / model unavailable:** Wait a moment and retry, or try a different model with `-m`.
- Do NOT retry more than twice (3 total attempts). If it keeps failing, tell the user.

## Example

Write prompt to file using the Write tool:

```
/tmp/codex-prompt.txt:
Review the authentication flow in src/auth/login.ts. Focus on security issues,
race conditions, and error handling. Be specific about line numbers.
```

Then run:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/codex-opinion.sh -o /tmp/codex-opinion.md "Read /tmp/codex-prompt.txt for your full instructions, then follow them."
```

Then read `/tmp/codex-opinion.md` for the response.

## Quick Reference

| Flag | Purpose |
|-|-|
| `-o FILE` | Write response to file |
| `-m MODEL` | Override model |
| `timeout: 600000` | Bash param for complex reviews |
| `run_in_background: true` | Bash param for very long reviews |

The wrapper always enforces `-s read-only --ephemeral`. You cannot override these.

## What NOT to Do

- **Do NOT call `codex exec` directly** — always use the wrapper script. It enforces read-only sandbox and prevents dangerous flag injection.
- **Do NOT pass prompts as inline Bash arguments** — shell metacharacters in review prompts will cause expansion or breakage. Always use the file-based approach above.
- **Do NOT call `codex --help`** — use `codex exec help` for help on the exec subcommand
- **Do NOT worry about the "Reading additional input from stdin..." message** — it is cosmetic noise, does not block execution
- **Do NOT add `-q` or `--quiet`** — these flags do not exist
- **Do NOT pipe stdin or use input redirection** — use the file-based prompt approach
- **Do NOT run codex exec inside another codex exec** — run it directly in Bash
