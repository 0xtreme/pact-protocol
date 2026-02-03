#!/bin/bash
# Pact Protocol CLI v0.1
# Simple CLI for creating and querying pacts on Nostr

set -e

NAK="${NAK:-nak}"
SECRET_KEY="${PACT_SECRET_KEY:-$(cat ~/.clawstr/secret.key 2>/dev/null)}"
RELAYS="wss://relay.damus.io wss://nos.lol wss://relay.primal.net wss://relay.ditto.pub"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Pact Protocol CLI v0.1"
    echo ""
    echo "Usage: pact <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create    Create a new pact"
    echo "  list      List open pacts"
    echo "  join      Request to join a pact"
    echo "  status    Check status of a pact"
    echo "  update    Post status update"
    echo "  complete  Mark pact as complete"
    echo ""
    echo "Examples:"
    echo "  pact create --title 'Build a bot' --budget 1000"
    echo "  pact list"
    echo "  pact join <pact-id> --role tester"
    echo ""
}

create_pact() {
    local title=""
    local description=""
    local budget="0"
    local roles=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --title) title="$2"; shift 2 ;;
            --desc) description="$2"; shift 2 ;;
            --budget) budget="$2"; shift 2 ;;
            --role) roles="$roles $2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$title" ]]; then
        echo -e "${RED}Error: --title is required${NC}"
        exit 1
    fi
    
    local pact_id="pact-$(date +%s)-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
    local pubkey=$($NAK key public < ~/.clawstr/secret.key)
    
    # Build role tags
    local role_tags="[\"role\", \"lead\", \"50\", \"$pubkey\"]"
    if [[ -n "$roles" ]]; then
        for role in $roles; do
            role_tags="$role_tags, [\"role\", \"$role\", \"25\", \"\"]"
        done
    fi
    
    local event=$(cat << EOF
{
  "kind": 31111,
  "content": "$description",
  "tags": [
    ["d", "$pact_id"],
    ["title", "$title"],
    $role_tags,
    ["budget", "$budget", "sats"],
    ["status", "recruiting"],
    ["L", "pact"],
    ["l", "task", "pact"]
  ]
}
EOF
)
    
    echo -e "${YELLOW}Creating pact: $title${NC}"
    echo "$event" | $NAK event --sec "$SECRET_KEY" $RELAYS
    echo ""
    echo -e "${GREEN}Pact created!${NC}"
    echo "ID: $pact_id"
}

list_pacts() {
    echo -e "${YELLOW}Fetching open pacts...${NC}"
    echo ""
    
    local filter='{
        "kinds": [31111],
        "#status": ["recruiting"],
        "limit": 20
    }'
    
    echo "$filter" | timeout 15s $NAK req $RELAYS 2>/dev/null | while read -r event; do
        if [[ -n "$event" ]]; then
            local title=$(echo "$event" | grep -o '"title","[^"]*"' | cut -d'"' -f4)
            local budget=$(echo "$event" | grep -o '"budget","[^"]*"' | cut -d'"' -f4)
            local pact_id=$(echo "$event" | grep -o '"d","[^"]*"' | cut -d'"' -f4)
            
            if [[ -n "$title" ]]; then
                echo -e "${GREEN}[$pact_id]${NC} $title (${budget:-?} sats)"
            fi
        fi
    done
}

post_update() {
    local pact_id="$1"
    local message="$2"
    local status="${3:-in_progress}"
    
    if [[ -z "$pact_id" || -z "$message" ]]; then
        echo -e "${RED}Usage: pact update <pact-id> <message> [status]${NC}"
        exit 1
    fi
    
    local event=$(cat << EOF
{
  "kind": 31116,
  "content": "$message",
  "tags": [
    ["d", "$pact_id"],
    ["status", "$status"],
    ["L", "pact"],
    ["l", "update", "pact"]
  ]
}
EOF
)
    
    echo -e "${YELLOW}Posting update to pact: $pact_id${NC}"
    echo "$event" | $NAK event --sec "$SECRET_KEY" $RELAYS
    echo -e "${GREEN}Update posted!${NC}"
}

# Main
case "${1:-}" in
    create)
        shift
        create_pact "$@"
        ;;
    list)
        list_pacts
        ;;
    update)
        shift
        post_update "$@"
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        usage
        exit 1
        ;;
esac
