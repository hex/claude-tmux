# ABOUTME: Closes a remote tmux pane by its @remote tag name.
# ABOUTME: Sends exit before killing the pane for a graceful disconnect.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: bash close.sh <name>"
    exit 1
fi

TARGET="$1"

if [[ -z "${TMUX:-}" ]]; then
    echo "Error: Must be run inside a tmux session." >&2
    exit 1
fi

PANE_ID=""
for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
    name=$(tmux show-options -p -t "$pane_id" -v @remote 2>/dev/null) || continue
    if [[ "$name" = "$TARGET" ]]; then
        PANE_ID="$pane_id"
        break
    fi
done

if [[ -z "$PANE_ID" ]]; then
    echo "Error: No remote pane found for '$TARGET'." >&2
    exit 1
fi

DEAD=$(tmux display-message -t "$PANE_ID" -p '#{pane_dead}' 2>/dev/null) || DEAD="1"
if [[ "$DEAD" = "0" ]]; then
    tmux send-keys -t "$PANE_ID" "exit" Enter
    sleep 0.5
fi
tmux kill-pane -t "$PANE_ID" 2>/dev/null || true

echo "Closed remote pane for ${TARGET} (${PANE_ID})"
