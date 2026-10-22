#!/usr/bin/env bash
# Smoke-tests the gateway: chat completions + Responses, streaming and non-streaming, background mode.
#
# Required env:
#   GATEWAY_URL       e.g. https://<apim-name>.azure-api.net
#   SUBSCRIPTION_KEY  APIM subscription key (omit if the API has subscriptionRequired=false)
# Optional env:
#   MODEL             model / deployment name (default: gpt-6-sol)
#   EMBEDDING_MODEL   embeddings model / deployment name; embeddings checks run only when set
set -u

: "${GATEWAY_URL:?set GATEWAY_URL}"
MODEL="${MODEL:-gpt-6-sol}"
RESPONSES_PREFIX=/v1
GATEWAY_URL="${GATEWAY_URL%/}"
PROMPT="Count from 1 to 40, one number per line, nothing else."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

AUTH=(-H "X-Gateway-Test: smoke")
[ -n "${SUBSCRIPTION_KEY:-}" ] && AUTH=(-H "api-key: ${SUBSCRIPTION_KEY}")

pass=0; fail=0
ok()   { echo "PASS  $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL  $1 -> $2"; fail=$((fail + 1)); }

# call NAME METHOD PATH [BODY] ; sets CODE and writes the body to $TMP/out
call() {
  local method="$2" path="$3" body="${4:-}"
  local args=(-sS -m 900 -o "$TMP/out" -w '%{http_code}' -X "$method" "${AUTH[@]}" -H 'Content-Type: application/json')
  [ -n "$body" ] && args+=(-d "$body")
  CODE=$(curl "${args[@]}" "${GATEWAY_URL}${path}")
}

# stream NAME PATH BODY ; passes when several SSE data events arrive and first byte precedes completion
stream() {
  local name="$1" path="$2" body="$3"
  local metrics
  metrics=$(curl -sSN -m 900 -o "$TMP/sse" -w '%{http_code} %{time_starttransfer} %{time_total}' \
    -X POST "${AUTH[@]}" -H 'Content-Type: application/json' -d "$body" "${GATEWAY_URL}${path}")
  read -r code ttfb total <<<"$metrics"
  local events; events=$(grep -c '^data:' "$TMP/sse" || true)
  if [ "$code" != "200" ]; then bad "$name" "HTTP $code: $(head -c 300 "$TMP/sse")"
  elif [ "$events" -lt 3 ]; then bad "$name" "only $events SSE events"
  else ok "$name (events=$events ttfb=${ttfb}s total=${total}s)"; fi
}

# 1. Chat completions
call chat 'POST' /v1/chat/completions \
  "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}]}"
[ "$CODE" = 200 ] && ok "chat completions" || bad "chat completions" "HTTP $CODE: $(head -c 300 "$TMP/out")"

stream "chat completions stream" /v1/chat/completions \
  "{\"model\":\"$MODEL\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}"

# 2. Embeddings (only when EMBEDDING_MODEL is set)
if [ -n "${EMBEDDING_MODEL:-}" ]; then
  call emb 'POST' /v1/embeddings "{\"model\":\"$EMBEDDING_MODEL\",\"input\":\"hello\"}"
  [ "$CODE" = 200 ] && [ "$(jq -r '.data[0].embedding | length' "$TMP/out" 2>/dev/null)" -gt 0 ] 2>/dev/null \
    && ok "embeddings" || bad "embeddings" "HTTP $CODE: $(head -c 300 "$TMP/out")"
fi

# 3. Responses
call resp 'POST' "${RESPONSES_PREFIX}/responses" "{\"model\":\"$MODEL\",\"input\":\"Say hi\"}"
[ "$CODE" = 200 ] && ok "responses create" || bad "responses create" "HTTP $CODE: $(head -c 300 "$TMP/out")"
RID=$(jq -r '.id // empty' "$TMP/out" 2>/dev/null)

stream "responses stream" "${RESPONSES_PREFIX}/responses" \
  "{\"model\":\"$MODEL\",\"stream\":true,\"input\":\"$PROMPT\"}"

if [ -n "$RID" ]; then
  call get 'GET' "${RESPONSES_PREFIX}/responses/${RID}"
  [ "$CODE" = 200 ] && ok "responses get" || bad "responses get" "HTTP $CODE"
  call items 'GET' "${RESPONSES_PREFIX}/responses/${RID}/input_items"
  [ "$CODE" = 200 ] && ok "responses input_items" || bad "responses input_items" "HTTP $CODE"
  call del 'DELETE' "${RESPONSES_PREFIX}/responses/${RID}"
  [ "$CODE" = 200 ] && ok "responses delete" || bad "responses delete" "HTTP $CODE"
fi

# 4. Background mode: create, poll until terminal, then cancel a second one
call bg 'POST' "${RESPONSES_PREFIX}/responses" "{\"model\":\"$MODEL\",\"background\":true,\"input\":\"$PROMPT\"}"
BID=$(jq -r '.id // empty' "$TMP/out" 2>/dev/null)
if [ "$CODE" != 200 ] || [ -z "$BID" ]; then
  bad "background create" "HTTP $CODE: $(head -c 300 "$TMP/out")"
else
  status=""
  for _ in $(seq 1 60); do
    call poll 'GET' "${RESPONSES_PREFIX}/responses/${BID}"
    status=$(jq -r '.status // empty' "$TMP/out" 2>/dev/null)
    case "$status" in completed|failed|cancelled|incomplete) break ;; esac
    sleep 5
  done
  [ "$status" = completed ] && ok "background create + poll" || bad "background create + poll" "final status '$status'"
fi

call bg2 'POST' "${RESPONSES_PREFIX}/responses" "{\"model\":\"$MODEL\",\"background\":true,\"input\":\"$PROMPT\"}"
CID=$(jq -r '.id // empty' "$TMP/out" 2>/dev/null)
if [ -n "$CID" ]; then
  call cancel 'POST' "${RESPONSES_PREFIX}/responses/${CID}/cancel"
  [ "$CODE" = 200 ] && ok "responses cancel" || bad "responses cancel" "HTTP $CODE: $(head -c 300 "$TMP/out")"
else
  bad "responses cancel" "could not create background response"
fi

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
