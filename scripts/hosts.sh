# ABOUTME: Manages saved remote host entries in a JSON configuration file.
# ABOUTME: Supports listing, adding, removing, and querying host definitions.
set -euo pipefail

usage() {
    echo "Usage: bash hosts.sh <hosts-json-path> <subcommand> [args...]"
    echo ""
    echo "Subcommands:"
    echo "  list                          List all saved hosts"
    echo "  add <name> <user@host> [desc] Add a new host"
    echo "  remove <name>                 Remove a host"
    echo "  get <name>                    Print full JSON for a host"
    echo "  import-ssh                    Import hosts from ~/.ssh/config"
    exit 1
}

if [[ $# -lt 2 ]]; then
    usage
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

HOSTS_FILE="$1"
SUBCOMMAND="$2"
shift 2

# Create the JSON file if it doesn't exist
if [[ ! -f "$HOSTS_FILE" ]]; then
    echo "{}" > "$HOSTS_FILE"
fi

case "$SUBCOMMAND" in
    list)
        COUNT=$(jq 'length' "$HOSTS_FILE")
        if [[ "$COUNT" -eq 0 ]]; then
            echo "No saved hosts."
            exit 0
        fi
        printf "%-20s %-30s %s\n" "NAME" "HOST" "DESCRIPTION"
        printf "%-20s %-30s %s\n" "----" "----" "-----------"
        jq -r 'to_entries[] | [.key, (.value.user + "@" + .value.host), (.value.description // "")] | @tsv' "$HOSTS_FILE" | \
            while IFS=$'\t' read -r name userhost desc; do
                printf "%-20s %-30s %s\n" "$name" "$userhost" "$desc"
            done
        ;;

    add)
        if [[ $# -lt 2 ]]; then
            echo "Usage: bash hosts.sh <hosts-json-path> add <name> <user@host> [description]" >&2
            exit 1
        fi
        NAME="$1"
        USERHOST="$2"
        DESC="${3:-}"

        if [[ "$USERHOST" != *@* ]]; then
            echo "Error: Second argument must be in user@host format." >&2
            exit 1
        fi

        USER="${USERHOST%%@*}"
        HOST="${USERHOST#*@}"

        if jq -e --arg name "$NAME" '.[$name]' "$HOSTS_FILE" &>/dev/null; then
            echo "Error: Host '$NAME' already exists. Remove it first or edit the JSON file." >&2
            exit 1
        fi

        jq --arg name "$NAME" \
           --arg user "$USER" \
           --arg host "$HOST" \
           --arg desc "$DESC" \
           '.[$name] = {user: $user, host: $host, description: $desc}' \
           "$HOSTS_FILE" > "${HOSTS_FILE}.tmp" && mv "${HOSTS_FILE}.tmp" "$HOSTS_FILE"

        echo "Added host '$NAME' (${USER}@${HOST})"
        ;;

    remove)
        if [[ $# -lt 1 ]]; then
            echo "Usage: bash hosts.sh <hosts-json-path> remove <name>" >&2
            exit 1
        fi
        NAME="$1"

        if ! jq -e --arg name "$NAME" '.[$name]' "$HOSTS_FILE" &>/dev/null; then
            echo "Error: Host '$NAME' not found." >&2
            exit 1
        fi

        jq --arg name "$NAME" 'del(.[$name])' "$HOSTS_FILE" > "${HOSTS_FILE}.tmp" && mv "${HOSTS_FILE}.tmp" "$HOSTS_FILE"

        echo "Removed host '$NAME'"
        ;;

    get)
        if [[ $# -lt 1 ]]; then
            echo "Usage: bash hosts.sh <hosts-json-path> get <name>" >&2
            exit 1
        fi
        NAME="$1"

        if ! jq -e --arg name "$NAME" '.[$name]' "$HOSTS_FILE" &>/dev/null; then
            echo "Error: Host '$NAME' not found." >&2
            exit 1
        fi

        jq --arg name "$NAME" '.[$name]' "$HOSTS_FILE"
        ;;

    import-ssh)
        SSH_CONFIG="${1:-$HOME/.ssh/config}"
        if [[ ! -f "$SSH_CONFIG" ]]; then
            echo "Error: SSH config not found at $SSH_CONFIG" >&2
            exit 1
        fi

        IMPORTED=0
        SKIPPED=0
        CURRENT_HOST=""
        CURRENT_HOSTNAME=""
        CURRENT_USER=""
        CURRENT_KEY=""

        flush_host() {
            if [[ -z "$CURRENT_HOST" || -z "$CURRENT_HOSTNAME" ]]; then
                return
            fi
            # Skip wildcard patterns
            if [[ "$CURRENT_HOST" == *"*"* || "$CURRENT_HOST" == *"?"* ]]; then
                return
            fi
            # Skip if already exists
            if jq -e --arg name "$CURRENT_HOST" '.[$name]' "$HOSTS_FILE" &>/dev/null; then
                echo "  skip: $CURRENT_HOST (already exists)"
                SKIPPED=$((SKIPPED + 1))
                return
            fi
            # Build the JSON entry
            local entry
            entry=$(jq -n \
                --arg host "$CURRENT_HOSTNAME" \
                --arg user "${CURRENT_USER:-$(whoami)}" \
                --arg key "$CURRENT_KEY" \
                '{host: $host, user: $user} + (if $key != "" then {key: $key} else {} end)')
            jq --arg name "$CURRENT_HOST" --argjson entry "$entry" \
                '.[$name] = $entry' "$HOSTS_FILE" > "${HOSTS_FILE}.tmp" && mv "${HOSTS_FILE}.tmp" "$HOSTS_FILE"
            echo "  added: $CURRENT_HOST (${CURRENT_USER:-$(whoami)}@${CURRENT_HOSTNAME})"
            IMPORTED=$((IMPORTED + 1))
        }

        while IFS= read -r line || [[ -n "$line" ]]; do
            # Strip leading/trailing whitespace
            trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            # Skip empty lines and comments
            [[ -z "$trimmed" || "$trimmed" == "#"* ]] && continue

            if [[ "$trimmed" =~ ^Host[[:space:]]+(.+)$ ]]; then
                flush_host
                CURRENT_HOST="${BASH_REMATCH[1]}"
                CURRENT_HOSTNAME=""
                CURRENT_USER=""
                CURRENT_KEY=""
            elif [[ "$trimmed" =~ ^HostName[[:space:]]+(.+)$ ]]; then
                CURRENT_HOSTNAME="${BASH_REMATCH[1]}"
            elif [[ "$trimmed" =~ ^User[[:space:]]+(.+)$ ]]; then
                CURRENT_USER="${BASH_REMATCH[1]}"
            elif [[ "$trimmed" =~ ^IdentityFile[[:space:]]+(.+)$ ]]; then
                CURRENT_KEY="${BASH_REMATCH[1]}"
            fi
        done < "$SSH_CONFIG"
        flush_host

        echo "Imported $IMPORTED host(s), skipped $SKIPPED."
        ;;

    *)
        echo "Error: Unknown subcommand '$SUBCOMMAND'" >&2
        usage
        ;;
esac
