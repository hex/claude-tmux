# claude-tmux

Connect to remote hosts via SSH in tmux panes. Manage saved hosts, open ad-hoc connections, and interact with remote sessions from Claude Code.

## Prerequisites

- [tmux](https://github.com/tmux/tmux) (3.0+)
- [jq](https://jqlang.github.io/jq/) (for JSON host management)
- SSH client with key-based authentication configured

## Installation

Register as an external plugin directory in Claude Code settings:

```json
// ~/.claude/settings.json
{
  "plugins": {
    "directories": [
      "~/.claude-sessions/claude-tmux"
    ]
  }
}
```

## Usage

### Interactive host selection

```
/remote
```

When called without arguments, presents saved hosts as selectable options.

### Connect to a saved host

```
/remote mac-mini
```

Idempotent -- if already connected to that host, reports the existing pane instead of creating a duplicate.

### Connect ad-hoc

```
/remote hex@192.168.1.50
```

### List saved hosts

```
/remote list
```

### Add a saved host

```
/remote add staging hex@staging.example.com
```

### Import from SSH config

```
/remote import-ssh
```

Parses `~/.ssh/config` and adds any hosts not already in `remote-hosts.json`.

### Close a remote pane

```
/remote close mac-mini
```

Sends `exit` for a graceful disconnect, then kills the pane.

### Check active remote panes

```
/remote status
```

Reports pane health (alive/dead) and offers to reconnect dead connections.

## Saved Hosts

Hosts are stored in `remote-hosts.json` at the plugin root:

```json
{
  "mac-mini": {
    "host": "192.168.1.98",
    "user": "hex",
    "key": "~/.ssh/id_ed25519",
    "ssh_opts": "-o IdentitiesOnly=yes",
    "description": "Mac Mini (wired LAN)"
  }
}
```

Fields:
- `host` (required) -- hostname or IP
- `user` (required) -- SSH username
- `port` (optional) -- SSH port (default: 22)
- `key` (optional) -- path to SSH private key
- `ssh_opts` (optional) -- additional SSH options
- `command` (optional) -- command to run on connect (e.g., `tmux new -A -s main`)
- `description` (optional) -- human-readable label

## Remote Pane Interaction

Once connected, interact with remote panes using tmux:

```bash
# Send a command
tmux send-keys -t <pane_id> "uptime" Enter

# Capture output
tmux capture-pane -t <pane_id> -p -S -10

# Find remote panes by @remote tag
for p in $(tmux list-panes -a -F '#{pane_id}'); do
  n=$(tmux show-options -p -t "$p" -v @remote 2>/dev/null) && [ -n "$n" ] && echo "$p $n"
done
```

The **Remote SSH via tmux** skill activates automatically when working with established remote connections, providing detailed patterns for sending commands, capturing output, and managing sessions.

## Plugin Structure

```
claude-tmux/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   └── remote.md
├── skills/
│   └── remote/
│       └── SKILL.md
├── scripts/
│   ├── connect.sh
│   └── hosts.sh
├── remote-hosts.json
└── README.md
```

## License

Copyright hexul. All rights reserved.
