#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: codex-opinion.sh [-o OUTPUT_FILE] [-m MODEL] PROMPT" >&2
  exit 1
}

output_file=""
model=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      shift
      output_file="${1:?missing output file argument}"
      shift
      ;;
    -m)
      shift
      model="${1:?missing model argument}"
      shift
      ;;
    -*)
      echo "Error: unknown flag: $1" >&2
      usage
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "Error: prompt argument required" >&2
  usage
fi

prompt="$1"

cmd=(codex exec -s read-only --ephemeral)

if [[ -n "$output_file" ]]; then
  cmd+=(-o "$output_file")
fi

if [[ -n "$model" ]]; then
  cmd+=(-m "$model")
fi

cmd+=("$prompt")

exec "${cmd[@]}"
