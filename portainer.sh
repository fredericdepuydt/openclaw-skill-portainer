#!/bin/bash
# Portainer CLI - control Docker via Portainer API or a compatible proxy
# Original author: Andy Steinberger (with help from Clawdbot Owen the Frog)
# Fork maintainer: Frederic + Ratchet

set -euo pipefail

PORTAINER_URL="${PORTAINER_URL:-}"
PORTAINER_API_KEY="${PORTAINER_API_KEY:-}"

if [[ -z "$PORTAINER_URL" || -z "$PORTAINER_API_KEY" ]]; then
  ENV_FILE="$HOME/.clawdbot/.env"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC2046
    export $(grep -E "^PORTAINER_" "$ENV_FILE" | xargs)
  fi
fi

if [[ -z "$PORTAINER_URL" ]]; then
  echo "Error: PORTAINER_URL must be set"
  exit 1
fi

AUTH_TOKEN="$PORTAINER_API_KEY"

BASE_URL="${PORTAINER_URL%/}"
PROXY_MODE=0
if [[ "$BASE_URL" == */portainer || "$BASE_URL" == */portainer/* ]]; then
  PROXY_MODE=1
fi

if [[ "$PROXY_MODE" -eq 1 ]]; then
  API="$BASE_URL"
  AUTH_HEADER="Authorization: Bearer $AUTH_TOKEN"
else
  API="$BASE_URL/api"
  AUTH_HEADER="X-API-Key: $AUTH_TOKEN"
fi

api_get() {
  curl -sS -H "$AUTH_HEADER" "$API$1"
}

api_post() {
  curl -sS -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" "$API$1" -d "$2"
}

api_put() {
  curl -sS -X PUT -H "$AUTH_HEADER" -H "Content-Type: application/json" "$API$1" -d "$2"
}

container_id_from_name() {
  local endpoint="$1"
  local name="$2"
  api_get "/endpoints/$endpoint/docker/containers/json?all=true" | jq -r ".[] | select(.Names[0] == \"/$name\") | .Id"
}

format_tsv() {
  if command -v column >/dev/null 2>&1; then
    column -t -s $'\t'
  else
    cat
  fi
}

case "${1:-}" in
  status)
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      api_get "/status" | jq -r '"Portainer v\(.payload.Version)"'
    else
      api_get "/status" | jq -r '"Portainer v\(.Version)"'
    fi
    ;;

  endpoints|envs)
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      api_get "/endpoints" | jq -r '.results[] | "\(.id): \(.name) (\(.type)) - \(if .status == 1 then "online" else "offline" end)"'
    else
      api_get "/endpoints" | jq -r '.[] | "\(.Id): \(.Name) (\(.Type == 1 | if . then "local" else "remote" end)) - \(if .Status == 1 then "online" else "offline" end)"'
    fi
    ;;

  containers)
    ENDPOINT="${2:-4}"
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      api_post "/containers" "{\"endpoint_id\": $ENDPOINT}" | jq -r '.results[] | "\(.name)\t\(.state)\t\(.status)"' | format_tsv
    else
      api_get "/endpoints/$ENDPOINT/docker/containers/json?all=true" | jq -r '.[] | "\(.Names[0] | ltrimstr("/"))\t\(.State)\t\(.Status)"' | format_tsv
    fi
    ;;

  stacks)
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      api_get "/stacks" | jq -r '.results[] | "\(.id): \(.name) - \(if .status == 1 then "active" else "inactive" end)"'
    else
      api_get "/stacks" | jq -r '.[] | "\(.Id): \(.Name) - \(if .Status == 1 then "active" else "inactive" end)"'
    fi
    ;;

  stack-info)
    STACK_ID="${2:-}"
    if [[ -z "$STACK_ID" ]]; then
      echo "Usage: portainer.sh stack-info <stack-id>"
      exit 1
    fi
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      api_post "/stacks-info" "{\"stack_id\": $STACK_ID}" | jq '.payload'
    else
      api_get "/stacks/$STACK_ID" | jq '{Id, Name, Status, EndpointId, GitConfig: .GitConfig.URL, UpdateDate: (.UpdateDate | todate)}'
    fi
    ;;

  networks)
    ENDPOINT="${2:-4}"
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      api_post "/networks" "{\"endpoint_id\": $ENDPOINT}" | jq -r '.results[] | "\(.name)\t\(.driver)\t\(.scope)\t\(.subnets | join(","))"' | format_tsv
    else
      api_get "/endpoints/$ENDPOINT/docker/networks" | jq -r '.[] | "\(.Name)\t\(.Driver)\t\(.Scope)\t\(.IPAM.Config // [] | map(.Subnet) | join(","))"' | format_tsv
    fi
    ;;

  container-info)
    CONTAINER="${2:-}"
    ENDPOINT="${3:-4}"
    if [[ -z "$CONTAINER" ]]; then
      echo "Usage: portainer.sh container-info <container-name> [endpoint-id]"
      exit 1
    fi
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      api_post "/container-info" "{\"container\": \"$CONTAINER\", \"endpoint_id\": $ENDPOINT}" | jq '.payload'
    else
      CONTAINER_ID="$(container_id_from_name "$ENDPOINT" "$CONTAINER")"
      if [[ -z "$CONTAINER_ID" ]]; then
        echo "Container '$CONTAINER' not found"
        exit 1
      fi
      api_get "/endpoints/$ENDPOINT/docker/containers/$CONTAINER_ID/json" | jq .
    fi
    ;;

  logs)
    CONTAINER="${2:-}"
    ENDPOINT="${3:-4}"
    TAIL="${4:-100}"
    if [[ -z "$CONTAINER" ]]; then
      echo "Usage: portainer.sh logs <container-name> [endpoint-id] [tail-lines]"
      exit 1
    fi
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      api_post "/logs" "{\"container\": \"$CONTAINER\", \"endpoint_id\": $ENDPOINT, \"tail\": $TAIL}" | jq -r '.logs[]'
    else
      CONTAINER_ID="$(container_id_from_name "$ENDPOINT" "$CONTAINER")"
      if [[ -z "$CONTAINER_ID" ]]; then
        echo "Container '$CONTAINER' not found"
        exit 1
      fi
      curl -sS -H "$AUTH_HEADER" "$API/endpoints/$ENDPOINT/docker/containers/$CONTAINER_ID/logs?stdout=true&stderr=true&tail=$TAIL" | strings
    fi
    ;;

  redeploy|start|stop|restart)
    if [[ "$PROXY_MODE" -eq 1 ]]; then
      echo "Error: '$1' is disabled in proxy mode (read-only)."
      exit 1
    fi

    case "$1" in
      redeploy)
        STACK_ID="${2:-}"
        if [[ -z "$STACK_ID" ]]; then
          echo "Usage: portainer.sh redeploy <stack-id>"
          exit 1
        fi
        STACK_INFO=$(api_get "/stacks/$STACK_ID")
        ENDPOINT_ID=$(echo "$STACK_INFO" | jq -r '.EndpointId')
        ENV_VARS=$(echo "$STACK_INFO" | jq -c '.Env')
        GIT_CRED_ID=$(echo "$STACK_INFO" | jq -r '.GitConfig.Authentication.GitCredentialID // 0')
        PAYLOAD=$(jq -n --argjson env "$ENV_VARS" --argjson gitCredId "$GIT_CRED_ID" '{env: $env, prune: false, pullImage: true, repositoryAuthentication: true, repositoryGitCredentialID: $gitCredId}')
        RESULT=$(api_put "/stacks/$STACK_ID/git/redeploy?endpointId=$ENDPOINT_ID" "$PAYLOAD")
        echo "$RESULT" | jq .
        ;;
      start|stop|restart)
        CONTAINER="${2:-}"
        ENDPOINT="${3:-4}"
        if [[ -z "$CONTAINER" ]]; then
          echo "Usage: portainer.sh $1 <container-name> [endpoint-id]"
          exit 1
        fi
        CONTAINER_ID="$(container_id_from_name "$ENDPOINT" "$CONTAINER")"
        if [[ -z "$CONTAINER_ID" ]]; then
          echo "Container '$CONTAINER' not found"
          exit 1
        fi
        api_post "/endpoints/$ENDPOINT/docker/containers/$CONTAINER_ID/$1" "{}" >/dev/null
        echo "Container '$CONTAINER' $1 requested"
        ;;
    esac
    ;;

  *)
    cat <<EOF
Portainer CLI (direct or proxy mode)

Usage: ./portainer.sh <command> [args]

Read commands:
  status
  endpoints
  containers [endpoint-id]
  stacks
  stack-info <stack-id>
  networks [endpoint-id]
  container-info <container-name> [endpoint-id]
  logs <container-name> [endpoint-id] [tail]

Write commands (direct mode only):
  redeploy <stack-id>
  start <container> [endpoint-id]
  stop <container> [endpoint-id]
  restart <container> [endpoint-id]

Environment:
  PORTAINER_URL     API base URL (for example: https://portainer:9443)
                    Can also point to a compatible proxy endpoint path.
  PORTAINER_API_KEY API token used for authentication
EOF
    ;;
esac
