---
description: Connect to remote hosts via SSH in tmux panes
argument-hint: <name|user@host|list|add|close|import-ssh|status>
allowed-tools: Bash(bash:*), Bash(tmux:*), AskUserQuestion
---

## Context

- Arguments: $ARGUMENTS

## Your task

Route based on the first argument provided:

### If arguments are empty:

First, load the saved hosts list:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/hosts.sh ${CLAUDE_PLUGIN_ROOT}/remote-hosts.json list
```

If there are saved hosts, use **AskUserQuestion** to present them as selectable options:
- Question: "Which remote host do you want to connect to?"
- Header: "Host"
- Options: one per saved host, using the host name as the label and the description (or user@host) as the option description

Then connect to the selected host using connect.sh.

If there are no saved hosts, tell the user and suggest `/remote add <name> <user@host>`.

### If first argument is `list`:

Run:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/hosts.sh ${CLAUDE_PLUGIN_ROOT}/remote-hosts.json list
```
Display the saved hosts table to the user.

### If first argument is `import-ssh`:

Import hosts from the user's SSH config:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/hosts.sh ${CLAUDE_PLUGIN_ROOT}/remote-hosts.json import-ssh
```
Report which hosts were imported and which were skipped (already in remote-hosts.json).

### If first argument is `add`:

Extract `<name>`, `<user@host>`, and optional `[description]` from the remaining arguments.

Run:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/hosts.sh ${CLAUDE_PLUGIN_ROOT}/remote-hosts.json add <name> <user@host> [description]
```
Confirm the host was added.

### If first argument is `close`:

Close a remote pane by name. Extract `<name>` from the remaining arguments.

Run:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/close.sh <name>
```
Report the result. If no pane is found for that name, say so.

### If first argument is `status`:

Find panes tagged with the `@remote` custom option and check health:
```
for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
  name=$(tmux show-options -p -t "$pane_id" -v @remote 2>/dev/null) && [ -n "$name" ] && \
    dead=$(tmux display-message -t "$pane_id" -p '#{pane_dead}') && echo "$pane_id $name dead=$dead"
done
```
Show active remote panes to the user. If none are found, say so. Flag any dead panes and offer to reconnect.

### Otherwise (connect to a host):

Treat the argument as a saved host name or a `user@host` target.

**Before connecting**, check if the argument is an exact match or user@host format. If it is neither, search for partial matches among saved host names:
```
jq -r 'keys[]' ${CLAUDE_PLUGIN_ROOT}/remote-hosts.json | grep -i "<argument>"
```

- If **one** match is found, use it as the target.
- If **multiple** matches are found, use **AskUserQuestion** to let the user pick:
  - Question: "Multiple hosts match '<argument>'. Which one?"
  - Header: "Host"
  - Options: one per matching host name, with description or user@host as the option description
- If **no** matches are found and the argument is not in `user@host` format, report the error and suggest `/remote list` to see available hosts.

Then connect:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/connect.sh ${CLAUDE_PLUGIN_ROOT}/remote-hosts.json <resolved-target>
```
Report the connection result including the pane ID and host info. If the script reports an existing connection, inform the user the pane is already active.
