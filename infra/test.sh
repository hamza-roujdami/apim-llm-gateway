#!/usr/bin/env bash
# Tests a deployed gateway: the infra, the policies and the Responses operations.
#
# Usage: infra/test.sh <resource-group>
#
# Needs: az (signed in), curl, jq. The resource group holds the APIM instance from main.bicep.
#
# Key mode (authMode=subscriptionKey): the script fetches the foundry-default key itself.
# Entra mode (authMode=entra): the script needs a caller that holds the gateway app role. Either
#   CALLER_TOKEN                        a ready access token, or
#   CALLER_CLIENT_ID + CALLER_CLIENT_SECRET   to get one (see: infra/entra-setup.sh caller ... --secret)
#
# Optional env:
#   MODEL             model name (default: gpt-6-sol)
#   DEPLOYMENT_NAME   name of the main deployment (default: main)
#   GATEWAY_URL       skip the lookup and test this URL (e.g. https://<apim>.azure-api.net/foundry)
#   SUBSCRIPTION_KEY  use this APIM subscription key instead of fetching foundry-default (key mode)
#   SKIP_INFRA=1      skip the az checks and run only the gateway checks (needs GATEWAY_URL, and
#                     AUTH_MODE=entra plus ENTRA_TENANT_ID and ENTRA_CLIENT_ID for Entra mode)
set -u

RG="${1:-}"
MODEL="${MODEL:-gpt-6-sol}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-main}"
API_ID=foundry
PROMPT="Count from 1 to 40, one number per line, nothing else."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0
ok()   { echo "PASS  $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL  $1 -> $2"; fail=$((fail + 1)); }
skp()  { echo "SKIP  $1"; skip=$((skip + 1)); }

AUTH_MODE="${AUTH_MODE:-key}"

# ---------- 1. Infra (az) ----------
if [ "${SKIP_INFRA:-}" != 1 ]; then
  [ -n "$RG" ] || { echo "usage: $0 <resource-group>"; exit 2; }
  echo "== Infra"
  SUB=$(az account show --query id -o tsv)
  APIM=$(az apim list -g "$RG" --query "[0].name" -o tsv)
  [ -n "$APIM" ] && ok "APIM instance found ($APIM)" || { bad "APIM instance" "none in $RG"; exit 1; }

  GATEWAY_URL="${GATEWAY_URL:-$(az apim show -n "$APIM" -g "$RG" --query gatewayUrl -o tsv)/$API_ID}"
  BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM"

  params=$(az deployment group show -g "$RG" -n "$DEPLOYMENT_NAME" --query properties.parameters -o json 2>/dev/null || echo '{}')
  outputs=$(az deployment group show -g "$RG" -n "$DEPLOYMENT_NAME" --query properties.outputs -o json 2>/dev/null || echo '{}')
  AUTH_MODE=$([ "$(echo "$params" | jq -r '.authMode.value // "subscriptionKey"')" = entra ] && echo entra || echo key)
  ok "auth mode: $AUTH_MODE"

  want_tier=$(echo "$params" | jq -r '.skuName.value // empty')
  live_tier=$(az apim show -n "$APIM" -g "$RG" --query sku.name -o tsv)
  if [ -z "$want_tier" ]; then skp "APIM tier (deployment parameters not readable)"
  elif [ "$want_tier" = "$live_tier" ]; then ok "APIM tier is $live_tier"
  else bad "APIM tier" "deployed with skuName=$want_tier but Azure reports $live_tier"; fi

  ops=$(az apim api operation list --service-name "$APIM" -g "$RG" --api-id "$API_ID" --query "length(@)" -o tsv 2>/dev/null)
  [ "$ops" = 5 ] && ok "API '$API_ID' has 5 operations" || bad "API operations" "found '${ops:-none}', expected 5"

  policy=$(az rest --method get --url "$BASE/apis/$API_ID/policies/policy?api-version=2024-05-01&format=rawxml" --query properties.value -o tsv 2>/dev/null)
  echo "$policy" | grep -q 'authentication-managed-identity' && ok "policy: managed identity auth" || bad "policy" "authentication-managed-identity missing"
  echo "$policy" | grep -q 'buffer-response="false"'         && ok "policy: streaming not buffered" || bad "policy" "buffer-response=false missing"
  echo "$policy" | grep -q '<retry'                          && ok "policy: retry" || bad "policy" "retry missing"
  echo "$policy" | grep -q 'llm-token-limit'                 && ok "policy: token limit" || skp "policy: token limit (off: tokensPerMinute=0)"
  echo "$policy" | grep -q 'llm-emit-token-metric'           && ok "policy: token metric" || skp "policy: token metric (off: deployMonitoring=false)"
  if [ "$AUTH_MODE" = entra ]; then
    echo "$policy" | grep -q 'validate-jwt' && ok "policy: validate-jwt (Entra)" || bad "policy" "validate-jwt missing in entra mode"
    sub_required=$(az apim api show --service-name "$APIM" -g "$RG" --api-id "$API_ID" --query subscriptionRequired -o tsv)
    [ "$sub_required" = false ] && ok "API does not also require a subscription key" || bad "API" "subscriptionRequired=$sub_required in entra mode"
  fi

  pid=$(az apim show -n "$APIM" -g "$RG" --query identity.principalId -o tsv)
  roles=$(az role assignment list --assignee "$pid" --all --query "[?roleDefinitionName=='Cognitive Services OpenAI User'] | length(@)" -o tsv 2>/dev/null)
  [ "${roles:-0}" -ge 1 ] && ok "APIM identity has 'Cognitive Services OpenAI User'" || bad "role assignment" "APIM identity has no OpenAI User role"

  foundry=$(echo "$outputs" | jq -r '.foundryAccountName.value // empty')
  if [ -n "$foundry" ]; then
    local_auth=$(az cognitiveservices account show -n "$foundry" -g "$RG" --query properties.disableLocalAuth -o tsv 2>/dev/null)
    [ "$local_auth" = true ] && ok "Foundry API keys are disabled (APIM identity is the only way in)" || skp "Foundry API keys are still enabled (disableFoundryLocalAuth=false or existing account)"
  fi

  if [ "$AUTH_MODE" = key ] && [ -z "${SUBSCRIPTION_KEY:-}" ]; then
    SUBSCRIPTION_KEY=$(az rest --method post --url "$BASE/subscriptions/$API_ID-default/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv)
  fi
  if [ "$AUTH_MODE" = entra ]; then
    ENTRA_TENANT_ID="${ENTRA_TENANT_ID:-$(az account show --query tenantId -o tsv)}"
    ENTRA_CLIENT_ID="${ENTRA_CLIENT_ID:-$(echo "$params" | jq -r '.entraClientId.value // empty')}"
  fi
fi

: "${GATEWAY_URL:?set GATEWAY_URL (or pass a resource group)}"
GATEWAY_URL="${GATEWAY_URL%/}"

if [ "$AUTH_MODE" = entra ]; then
  if [ -z "${CALLER_TOKEN:-}" ]; then
    : "${CALLER_CLIENT_ID:?Entra mode needs CALLER_TOKEN, or CALLER_CLIENT_ID and CALLER_CLIENT_SECRET}"
    : "${CALLER_CLIENT_SECRET:?Entra mode needs CALLER_TOKEN, or CALLER_CLIENT_ID and CALLER_CLIENT_SECRET}"
    CALLER_TOKEN=$(curl -sS -X POST "https://login.microsoftonline.com/${ENTRA_TENANT_ID}/oauth2/v2.0/token" \
      --data-urlencode "client_id=${CALLER_CLIENT_ID}" --data-urlencode "client_secret=${CALLER_CLIENT_SECRET}" \
      --data-urlencode "scope=api://${ENTRA_CLIENT_ID}/.default" --data-urlencode "grant_type=client_credentials" | jq -r '.access_token // empty')
    [ -n "$CALLER_TOKEN" ] || { bad "caller token" "could not get a token (is the role granted? see infra/entra-setup.sh)"; echo; echo "passed=$pass failed=$fail skipped=$skip"; exit 1; }
  fi
  AUTH=(-H "Authorization: Bearer ${CALLER_TOKEN}")
else
  AUTH=(-H "api-key: ${SUBSCRIPTION_KEY:-}")
fi

# call METHOD PATH [BODY] ; sets CODE, writes the body to $TMP/out and the headers to $TMP/hdr
call() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -m 900 -o "$TMP/out" -D "$TMP/hdr" -w '%{http_code}' -X "$method" "${AUTH[@]}" -H 'Content-Type: application/json')
  [ -n "$body" ] && args+=(-d "$body")
  CODE=$(curl "${args[@]}" "${GATEWAY_URL}${path}")
}

# status_with HEADER... ; the status code of a create call that sends the given headers only
status_with() {
  curl -sS -o /dev/null -w '%{http_code}' -X POST "$@" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"input\":\"hi\"}" "${GATEWAY_URL}/v1/responses"
}

# ---------- 2. Gateway: access and policies ----------
echo "== Policies"
CODE=$(status_with)
[ "$CODE" = 401 ] && ok "no credentials are rejected (401)" || bad "no credentials" "expected 401, got $CODE"

if [ "$AUTH_MODE" = entra ]; then
  CODE=$(status_with -H "Authorization: Bearer not.a.token")
  [ "$CODE" = 401 ] && ok "garbage token is rejected (401)" || bad "garbage token" "expected 401, got $CODE"

  wrong_aud=$(az account get-access-token --resource https://management.azure.com --query accessToken -o tsv 2>/dev/null)
  if [ -n "$wrong_aud" ]; then
    CODE=$(status_with -H "Authorization: Bearer $wrong_aud")
    [ "$CODE" = 401 ] && ok "valid token for another audience is rejected (401)" || bad "wrong audience" "expected 401, got $CODE"
  else
    skp "token for another audience (az is not signed in)"
  fi

  CODE=$(status_with -H "api-key: anything")
  [ "$CODE" = 401 ] && ok "a subscription key alone is not accepted (401)" || bad "key in entra mode" "expected 401, got $CODE"
else
  CODE=$(status_with -H 'api-key: not-a-real-key')
  [ "$CODE" = 401 ] && ok "wrong key is rejected (401)" || bad "wrong key" "expected 401, got $CODE"
fi

# ---------- 3. Gateway: Responses operations ----------
echo "== Operations"
call POST /v1/responses "{\"model\":\"$MODEL\",\"input\":\"Say hi\"}"
[ "$CODE" = 200 ] && ok "responses create" || bad "responses create" "HTTP $CODE: $(head -c 300 "$TMP/out")"
RID=$(jq -r '.id // empty' "$TMP/out" 2>/dev/null)

if grep -qi '^x-remaining-tokens:' "$TMP/hdr"; then ok "token limit header present (x-remaining-tokens)"
else skp "token limit header (limit off or not returned)"; fi

# Stream: several SSE events must arrive, and the first byte must come well before the end.
metrics=$(curl -sSN -m 900 -o "$TMP/sse" -w '%{http_code} %{time_starttransfer} %{time_total}' -X POST "${AUTH[@]}" \
  -H 'Content-Type: application/json' -d "{\"model\":\"$MODEL\",\"stream\":true,\"input\":\"$PROMPT\"}" "${GATEWAY_URL}/v1/responses")
read -r scode ttfb total <<<"$metrics"
events=$(grep -c '^data:' "$TMP/sse" || true)
if [ "$scode" != 200 ]; then bad "responses stream" "HTTP $scode: $(head -c 300 "$TMP/sse")"
elif [ "$events" -lt 3 ]; then bad "responses stream" "only $events SSE events"
elif awk -v a="$ttfb" -v b="$total" 'BEGIN { exit !(a < b * 0.8) }'; then ok "responses stream, unbuffered (events=$events ttfb=${ttfb}s total=${total}s)"
else bad "responses stream" "first byte at ${ttfb}s of ${total}s: looks buffered"; fi

if [ -n "$RID" ]; then
  call GET "/v1/responses/${RID}";             [ "$CODE" = 200 ] && ok "responses get"         || bad "responses get" "HTTP $CODE"
  call GET "/v1/responses/${RID}/input_items"; [ "$CODE" = 200 ] && ok "responses input_items" || bad "responses input_items" "HTTP $CODE"
  call DELETE "/v1/responses/${RID}";          [ "$CODE" = 200 ] && ok "responses delete"      || bad "responses delete" "HTTP $CODE"
fi

# Background mode: create and poll until it ends, then cancel a second one.
call POST /v1/responses "{\"model\":\"$MODEL\",\"background\":true,\"input\":\"$PROMPT\"}"
BID=$(jq -r '.id // empty' "$TMP/out" 2>/dev/null)
if [ "$CODE" != 200 ] || [ -z "$BID" ]; then
  bad "background create" "HTTP $CODE: $(head -c 300 "$TMP/out")"
else
  status=""
  for _ in $(seq 1 60); do
    call GET "/v1/responses/${BID}"
    status=$(jq -r '.status // empty' "$TMP/out" 2>/dev/null)
    case "$status" in completed|failed|cancelled|incomplete) break ;; esac
    sleep 5
  done
  [ "$status" = completed ] && ok "background create + poll" || bad "background create + poll" "final status '$status'"
fi

call POST /v1/responses "{\"model\":\"$MODEL\",\"background\":true,\"input\":\"$PROMPT\"}"
CID=$(jq -r '.id // empty' "$TMP/out" 2>/dev/null)
if [ -n "$CID" ]; then
  call POST "/v1/responses/${CID}/cancel"
  [ "$CODE" = 200 ] && ok "responses cancel" || bad "responses cancel" "HTTP $CODE: $(head -c 300 "$TMP/out")"
else
  bad "responses cancel" "could not create background response"
fi

echo; echo "passed=$pass failed=$fail skipped=$skip"
[ "$fail" -eq 0 ]
