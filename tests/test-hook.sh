#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/plugins/claude-token-usage/hooks/stop-token-usage.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

transcript="$tmp/session.jsonl"
cat >"$transcript" <<'JSONL'
{"type":"assistant","requestId":"old","message":{"id":"old-message","usage":{"input_tokens":999999,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
{"type":"user","isSidechain":false,"isMeta":false,"message":{"role":"user","content":"Measure this turn"}}
{"type":"assistant","requestId":"request-1","message":{"id":"message-1","usage":{"input_tokens":2,"output_tokens":75,"cache_creation_input_tokens":0,"cache_read_input_tokens":4480}}}
{"type":"user","isSidechain":false,"isMeta":false,"message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
{"type":"assistant","requestId":"request-1","message":{"id":"message-1","usage":{"input_tokens":2,"output_tokens":75,"cache_creation_input_tokens":0,"cache_read_input_tokens":4480}}}
{"type":"assistant","requestId":"request-2","message":{"id":"message-2","usage":{"input_tokens":3,"output_tokens":25,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000}}}
JSONL

output="$(jq -nc --arg transcript_path "$transcript" '{transcript_path: $transcript_path}' | "$hook")"
expected='turn total: 5,685 tokens (fresh input 5, cache read 5,480, cache new 100, output 100)'

jq -e --arg expected "$expected" '.systemMessage | contains($expected)' <<<"$output" >/dev/null
printf 'Claude hook test passed: %s\n' "$(jq -r '.systemMessage' <<<"$output")"
