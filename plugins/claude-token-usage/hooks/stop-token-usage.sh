#!/usr/bin/env bash
set -uo pipefail

now="$(date +'%H:%M:%S')"

emit() {
  jq -nc --arg msg "$1" '{systemMessage: $msg}'
}

if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"%s | tokens unavailable: jq not found"}\n' "$now"
  exit 0
fi

input="$(cat)"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"

if [[ -z "$transcript_path" || ! -r "$transcript_path" ]]; then
  emit "$now | tokens unavailable: transcript not readable"
  exit 0
fi

read_stats() {
  jq -rs '
    def num: if type == "number" then . elif type == "string" then (tonumber? // 0) else 0 end;
    def human_prompt:
      .type == "user"
      and .isSidechain != true
      and .isMeta != true
      and .message.role == "user"
      and (
        if (.message.content | type) == "array" then
          any(.message.content[]?; .type != "tool_result")
        elif (.message.content | type) == "string" then
          (.message.content | test("^<local-command-|^<command-") | not)
        else
          false
        end
      );
    def usage:
      .type == "assistant"
      and .isSidechain != true
      and .isApiErrorMessage != true
      and .message.usage?;
    def empty_stats:
      {
        seen: {},
        last: null,
        input: 0,
        output: 0,
        cache_create: 0,
        cache_read: 0
      };
    reduce .[] as $r (empty_stats;
      if ($r | human_prompt) then
        empty_stats
      elif ($r | usage) then
        ($r.message.usage | {
          input: ((.input_tokens // 0) | num),
          output: ((.output_tokens // 0) | num),
          cache_create: ((.cache_creation_input_tokens // 0) | num),
          cache_read: ((.cache_read_input_tokens // 0) | num)
        }) as $v
        | ($r.requestId // $r.message.id // "\($v.input)|\($v.output)|\($v.cache_create)|\($v.cache_read)") as $key
        | .last = $v
        | if .seen[$key] then
            .
          else
            .seen[$key] = true
            | .input += $v.input
            | .output += $v.output
            | .cache_create += $v.cache_create
            | .cache_read += $v.cache_read
          end
      else
        .
      end
    )
  ' "$transcript_path" 2>/dev/null || true
}

stats=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  stats="$(read_stats)"
  if [[ -n "$stats" ]] && jq -e '.last != null' <<<"$stats" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

if [[ -z "$stats" ]]; then
  emit "$now | tokens unavailable: transcript parse failed"
  exit 0
fi

message="$(
  jq -r --arg now "$now" '
    def comma:
      tostring as $s
      | ($s | length) as $len
      | reduce range(0; $len) as $i ("";
          . + (if $i > 0 and (($len - $i) % 3 == 0) then "," else "" end) + $s[$i:$i+1]
        );

    if .last == null then
      "\($now) | tokens unavailable: usage not flushed yet"
    else
      (.input + .output + .cache_create + .cache_read) as $turn_total
      | "\($now) | turn total: \($turn_total | comma) tokens (fresh input \(.input | comma), cache read \(.cache_read | comma), cache new \(.cache_create | comma), output \(.output | comma))"
    end
  ' <<<"$stats"
)"

emit "$message"
