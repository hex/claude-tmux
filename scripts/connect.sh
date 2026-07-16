#!/usr/bin/env bash
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
USE_ET=""

if [[ -f "$HOSTS_FILE" ]] && jq -e --arg name "$TARGET" '.[$name]' "$HOSTS_FILE" &>/dev/null; then
    HOST=$(jq -r --arg name "$TARGET" '.[$name].host' "$HOSTS_FILE")
    USER=$(jq -r --arg name "$TARGET" '.[$name].user' "$HOSTS_FILE")
    PORT=$(jq -r --arg name "$TARGET" '.[$name].port // empty' "$HOSTS_FILE")
    KEY=$(jq -r --arg name "$TARGET" '.[$name].key // empty' "$HOSTS_FILE")
    SSH_OPTS=$(jq -r --arg name "$TARGET" '.[$name].ssh_opts // empty' "$HOSTS_FILE")
    REMOTE_CMD=$(jq -r --arg name "$TARGET" '.[$name].command // empty' "$HOSTS_FILE")
    USE_ET=$(jq -r --arg name "$TARGET" '.[$name].use_et // empty' "$HOSTS_FILE")
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
        # The command is typed into a shell via send-keys, so the path is
        # evaluated a second time there. printf %q escapes it to a single
        # literal token, safe against quotes and command substitution.
        local expanded_key
        expanded_key=$(printf '%q' "${KEY/#\~/$HOME}")
        cmd="$cmd -i $expanded_key"
    fi
    [[ -n "$SSH_OPTS" ]] && cmd="$cmd $SSH_OPTS"
    cmd="$cmd ${USER}@${HOST}"
    # %q escapes the remote command to a single literal token so the pane
    # shell passes it to ssh verbatim without re-parsing quotes or $(...)
    [[ -n "$REMOTE_CMD" ]] && cmd="$cmd $(printf '%q' "$REMOTE_CMD")"
    echo "$cmd"
}

build_et_cmd() {
    local cmd="et"
    [[ -n "$PORT" ]] && cmd="$cmd --port $PORT"
    [[ -n "$REMOTE_CMD" ]] && cmd="$cmd -c $(printf '%q' "$REMOTE_CMD")"
    cmd="$cmd ${USER}@${HOST}"
    echo "$cmd"
}

# Poll pane output for connection errors; returns 0 if a failure is seen.
# Exits early once a shell prompt appears (connection established or the
# local shell returned alongside an error line, which the pattern catches).
connection_failed() {
    local pane="$1"
    local output
    for i in $(seq 1 8); do
        sleep 0.5
        output=$(tmux capture-pane -t "$pane" -p 2>/dev/null) || return 0
        if echo "$output" | grep -qiE "Could not reach|Connection refused|Connection timed out|No route to host|Name or service not known|nodename nor servname|Permission denied|Connection closed by"; then
            return 0
        fi
        if echo "$output" | grep -qE '[#$%>❯] *$' && [[ $i -ge 3 ]]; then
            return 1
        fi
    done
    return 1
}

# Split from the calling pane so the new pane opens in the caller's window.
# Without this, tmux splits the session's active window, which under iTerm2's
# tmux control mode is a different tab than the one the caller is in.
if [[ -n "${TMUX_PANE:-}" ]]; then
    PANE_ID=$(tmux split-window -h -d -P -F '#{pane_id}' -t "$TMUX_PANE")
else
    PANE_ID=$(tmux split-window -h -d -P -F '#{pane_id}')
fi

# Tag pane with custom option for reliable tracking (escape sequences can't overwrite this)
tmux set-option -p -t "$PANE_ID" @remote "${DISPLAY_NAME}"

# Use et only when explicitly configured for this host
if [[ "$USE_ET" = "true" ]] && command -v et &>/dev/null; then
    CONN_CMD=$(build_et_cmd)
    tmux send-keys -t "$PANE_ID" "$CONN_CMD" Enter

    if connection_failed "$PANE_ID"; then
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

# Verify the connection did not fail outright
if connection_failed "$PANE_ID"; then
    ERROR_LINES=$(tmux capture-pane -t "$PANE_ID" -p 2>/dev/null | grep -v '^$' | tail -3) || ERROR_LINES=""
    tmux kill-pane -t "$PANE_ID" 2>/dev/null || true
    echo "Error: Connection to ${USER}@${HOST} failed:" >&2
    [[ -n "$ERROR_LINES" ]] && echo "$ERROR_LINES" >&2
    exit 1
fi

DEAD=$(tmux display-message -t "$PANE_ID" -p '#{pane_dead}' 2>/dev/null) || DEAD="1"
if [[ "$DEAD" = "1" ]]; then
    echo "Error: Connection pane died immediately. Check host reachability." >&2
    exit 1
fi

echo "Connected to ${USER}@${HOST} in pane ${PANE_ID} (remote:${DISPLAY_NAME}) via ${CONN_TYPE}"
