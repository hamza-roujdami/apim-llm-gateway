#!/usr/bin/env bash
# Sets up the Entra ID side of authMode=entra: the gateway app registration, and who may call it.
#
#   infra/entra-setup.sh gateway [display-name]
#       Creates (or reuses) the gateway app registration: v2 tokens, identifier URI api://<client-id>,
#       one app role (Gateway.Invoke), and "assignment required" so only granted callers get a token.
#       Prints the client id to use as the entraClientId parameter.
#
#   infra/entra-setup.sh grant <gateway-client-id> <principal-object-id>
#       Grants the app role to a managed identity or service principal (use its object id).
#
#   infra/entra-setup.sh caller <gateway-client-id> <display-name> [--secret]
#       Creates (or reuses) an app registration for a caller that is not an Azure managed identity, and
#       grants it the role. With --secret it also creates a client secret and prints it once. Prefer a managed
#       identity with "grant"; a secret is for tests and for callers outside Azure.
#
# Needs: az (signed in as someone who can create app registrations), jq.
set -euo pipefail

ROLE_VALUE="Gateway.Invoke"
ROLE_ID="5e2f6a0c-7a4b-4c1e-9a3d-1b8c0f7d2e41"
GRAPH="https://graph.microsoft.com/v1.0"
TENANT="$(az account show --query tenantId -o tsv)"

app_object_id() { az ad app show --id "$1" --query id -o tsv; }
sp_object_id()  { az ad sp show --id "$1" --query id -o tsv 2>/dev/null || true; }

ensure_sp() {
  local sp; sp="$(sp_object_id "$1")"
  [ -n "$sp" ] || sp="$(az ad sp create --id "$1" --query id -o tsv)"
  echo "$sp"
}

# ensure_app NAME -> prints the client id, creating the app registration if there is none with that name
ensure_app() {
  local id; id="$(az ad app list --display-name "$1" --query "[0].appId" -o tsv)"
  [ -n "$id" ] || id="$(az ad app create --display-name "$1" --sign-in-audience AzureADMyOrg --query appId -o tsv)"
  echo "$id"
}

cmd="${1:-}"
case "$cmd" in
  gateway)
    name="${2:-llm-gateway}"
    client_id="$(ensure_app "$name")"
    obj="$(app_object_id "$client_id")"
    az rest --method patch --url "$GRAPH/applications/$obj" --headers "Content-Type=application/json" --body "$(jq -n \
      --arg uri "api://$client_id" --arg id "$ROLE_ID" --arg value "$ROLE_VALUE" \
      '{identifierUris: [$uri],
        api: {requestedAccessTokenVersion: 2},
        appRoles: [{id: $id, value: $value, displayName: "Invoke the LLM gateway", isEnabled: true,
                    description: "Call the LLM gateway on behalf of the calling application.",
                    allowedMemberTypes: ["Application"]}]}')" >/dev/null
    sp="$(ensure_sp "$client_id")"
    az rest --method patch --url "$GRAPH/servicePrincipals/$sp" --headers "Content-Type=application/json" \
      --body '{"appRoleAssignmentRequired": true}' >/dev/null
    echo "Gateway app registration '$name' is ready."
    echo "entraClientId = $client_id"
    echo "entraTenantId = $TENANT"
    ;;

  grant)
    gw="${2:?usage: grant <gateway-client-id> <principal-object-id>}"; principal="${3:?usage: grant <gateway-client-id> <principal-object-id>}"
    gw_sp="$(sp_object_id "$gw")"; [ -n "$gw_sp" ] || { echo "gateway service principal not found: run '$0 gateway' first" >&2; exit 1; }
    existing="$(az rest --method get --url "$GRAPH/servicePrincipals/$principal/appRoleAssignments" \
      --query "value[?resourceId=='$gw_sp' && appRoleId=='$ROLE_ID'] | length(@)" -o tsv)"
    if [ "$existing" = 0 ]; then
      az rest --method post --url "$GRAPH/servicePrincipals/$principal/appRoleAssignments" --headers "Content-Type=application/json" \
        --body "$(jq -n --arg p "$principal" --arg r "$gw_sp" --arg a "$ROLE_ID" '{principalId: $p, resourceId: $r, appRoleId: $a}')" >/dev/null
      echo "Granted $ROLE_VALUE to $principal."
    else
      echo "$principal already has $ROLE_VALUE."
    fi
    ;;

  caller)
    gw="${2:?usage: caller <gateway-client-id> <display-name> [--secret]}"; name="${3:?usage: caller <gateway-client-id> <display-name> [--secret]}"
    client_id="$(ensure_app "$name")"
    sp="$(ensure_sp "$client_id")"
    "$0" grant "$gw" "$sp"
    echo "caller client id = $client_id"
    if [ "${4:-}" = "--secret" ]; then
      # 30 days: short on purpose, and many tenants cap secret lifetime
      end="$(date -u -d '+30 days' +%F 2>/dev/null || date -u -v+30d +%F)"
      secret="$(az ad app credential reset --id "$client_id" --append --display-name "gateway-caller" --end-date "$end" --query password -o tsv)"
      echo "caller secret    = $secret   (valid until $end, shown once; store it in a vault)"
    fi
    echo "token scope      = api://$gw/.default"
    ;;

  *)
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
