# ABOUTME: Opens a tmux pane with an SSH connection to a remote host.
# ABOUTME: Reads host config from remote-hosts.json or accepts ad-hoc user@host.
set -euo pipefail

usage() {
    echo "Usage: bash connect.sh <hosts-json-path> <name|user@host>"
    exit 1
}

if [[ $# -lt 2 ]]; then
    usage
fi

HOSTS_FILE="$1"
TARGET="$2"

if [[ -z "${TMUX:-}" ]]; then
    echo "Error: Must be run inside a tmux session." >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# Check for an existing pane tagged with @remote matching this target
find_existing_pane() {
    local target="$1"
    for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
        name=$(tmux show-options -p -t "$pane_id" -v @remote 2>/dev/null) || continue
        if [[ "$name" = "$target" ]]; then
            echo "$pane_id"
            return 0
        fi
    done
    return 1
}

EXISTING_PANE=$(find_existing_pane "$TARGET") || true
if [[ -n "$EXISTING_PANE" ]]; then
    DEAD=$(tmux display-message -t "$EXISTING_PANE" -p '#{pane_dead}' 2>/dev/null) || DEAD="1"
    if [[ "$DEAD" = "0" ]]; then
        echo "Already connected to ${TARGET} in pane ${EXISTING_PANE}"
        exit 0
    else
        # Dead pane -- kill it and create a fresh one
        tmux kill-pane -t "$EXISTING_PANE" 2>/dev/null || true
    fi
fi

HOST=""
USER=""
PORT=""
KEY=""
SSH_OPTS=""
REMOTE_CMD=""
DISPLAY_NAME=""

if [[ -f "$HOSTS_FILE" ]] && jq -e --arg name "$TARGET" '.[$name]' "$HOSTS_FILE" &>/dev/null; then
    HOST=$(jq -r --arg name "$TARGET" '.[$name].host' "$HOSTS_FILE")
    USER=$(jq -r --arg name "$TARGET" '.[$name].user' "$HOSTS_FILE")
    PORT=$(jq -r --arg name "$TARGET" '.[$name].port // empty' "$HOSTS_FILE")
    KEY=$(jq -r --arg name "$TARGET" '.[$name].key // empty' "$HOSTS_FILE")
    SSH_OPTS=$(jq -r --arg name "$TARGET" '.[$name].ssh_opts // empty' "$HOSTS_FILE")
    REMOTE_CMD=$(jq -r --arg name "$TARGET" '.[$name].command // empty' "$HOSTS_FILE")
    DISPLAY_NAME="$TARGET"
elif [[ "$TARGET" == *@* ]]; then
    USER="${TARGET%%@*}"
    HOST="${TARGET#*@}"
    DISPLAY_NAME="$TARGET"
else
    echo "Error: '$TARGET' is not a saved host name and not in user@host format." >&2
    exit 1
fi

if [[ -z "$HOST" || "$HOST" = "null" || -z "$USER" || "$USER" = "null" ]]; then
    echo "Error: Host entry for '$TARGET' is missing required host or user field." >&2
    exit 1
fi

build_ssh_cmd() {
    local cmd="ssh -t"
    [[ -n "$PORT" ]] && cmd="$cmd -p $PORT"
    if [[ -n "$KEY" ]]; then
        local expanded_key
        expanded_key=$(eval echo "$KEY")
        cmd="$cmd -i $expanded_key"
    fi
    [[ -n "$SSH_OPTS" ]] && cmd="$cmd $SSH_OPTS"
    cmd="$cmd ${USER}@${HOST}"
    [[ -n "$REMOTE_CMD" ]] && cmd="$cmd '${REMOTE_CMD}'"
    echo "$cmd"
}

build_et_cmd() {
    local cmd="et"
    [[ -n "$PORT" ]] && cmd="$cmd --port $PORT"
    [[ -n "$REMOTE_CMD" ]] && cmd="$cmd -c \"${REMOTE_CMD}\""
    cmd="$cmd ${USER}@${HOST}"
    echo "$cmd"
}

PANE_ID=$(tmux split-window -h -d -P -F '#{pane_id}')

# Tag pane with custom option for reliable tracking (escape sequences can't overwrite this)
tmux set-option -p -t "$PANE_ID" @remote "${DISPLAY_NAME}"

# Try et first, fall back to ssh on failure
HAS_ET=false
command -v et &>/dev/null && HAS_ET=true

if [[ "$HAS_ET" = true ]]; then
    CONN_CMD=$(build_et_cmd)
    tmux send-keys -t "$PANE_ID" "$CONN_CMD" Enter

    # Wait and check for et failure
    ET_FAILED=false
    for i in $(seq 1 8); do
        sleep 0.5
        OUTPUT=$(tmux capture-pane -t "$PANE_ID" -p 2>/dev/null) || break
        if echo "$OUTPUT" | grep -qiE "Could not reach|Connection refused|Connection timed out|No route to host|Name or service not known"; then
            ET_FAILED=true
            break
        fi
        # If we see a remote prompt, et succeeded
        if echo "$OUTPUT" | grep -qE '[#$%>❯] *$' && [[ $i -ge 3 ]]; then
            break
        fi
    done

    if [[ "$ET_FAILED" = true ]]; then
        echo "et failed, falling back to ssh..." >&2
        # Clear the pane and send ssh command instead
        tmux send-keys -t "$PANE_ID" C-c
        sleep 0.2
        CONN_CMD=$(build_ssh_cmd)
        tmux send-keys -t "$PANE_ID" "$CONN_CMD" Enter
        CONN_TYPE="ssh (et unavailable on remote)"
    else
        CONN_TYPE="et"
    fi
else
    CONN_CMD=$(build_ssh_cmd)
    tmux send-keys -t "$PANE_ID" "$CONN_CMD" Enter
    CONN_TYPE="ssh"
fi

# Verify the connection attempt started
sleep 1
DEAD=$(tmux display-message -t "$PANE_ID" -p '#{pane_dead}' 2>/dev/null) || DEAD="1"
if [[ "$DEAD" = "1" ]]; then
    echo "Error: Connection pane died immediately. Check host reachability." >&2
    exit 1
fi

echo "Connected to ${USER}@${HOST} in pane ${PANE_ID} (remote:${DISPLAY_NAME}) via ${CONN_TYPE}"
