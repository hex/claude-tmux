# claude-tmux

Connect to remote hosts via SSH in tmux panes. Manage saved hosts, open ad-hoc connections, and interact with remote sessions from Claude Code.

## Features

- **Saved host management** -- add, remove, list, and connect to named hosts from a JSON config
- **Ad-hoc connections** -- connect to any `user@host` without saving it first
- **Idempotent connections** -- reconnects dead panes, reuses live ones
- **SSH config import** -- bulk-import hosts from `~/.ssh/config`
- **Eternal Terminal support** -- prefers `et` over `ssh` when available for persistent connections
- **Pane health monitoring** -- check which remote panes are alive or dead
- **Graceful disconnect** -- sends `exit` before killing panes

## Installation

### From marketplace (recommended)

```bash
# Add the hex-plugins marketplace (once)
/plugin marketplace add hex/claude-marketplace

# Install the plugin
/plugin install claude-tmux
```

### From GitHub

```bash
/plugin install hex/claude-tmux
```

### Manual

```bash
git clone https://github.com/hex/claude-tmux.git
claude --plugin-dir /path/to/claude-tmux
```

## Requirements

- [tmux](https://github.com/tmux/tmux) (3.0+)
- [jq](https://jqlang.github.io/jq/) (for JSON host management)
- SSH client with key-based authentication configured
- [Eternal Terminal](https://eternalterminal.dev/) (optional) -- preferred over SSH when available

## Usage

### Interactive host selection

```
/remote
```

When called without arguments, presents saved hosts as selectable options.

### Connect to a saved host

```
/remote my-server
```

Idempotent -- if already connected to that host, reports the existing pane instead of creating a duplicate.

### Connect ad-hoc

```
/remote user@192.168.1.50
```

### List saved hosts

```
/remote list
```

### Add a saved host

```
/remote add staging deploy@staging.example.com
```

### Import from SSH config

```
/remote import-ssh
```

Parses `~/.ssh/config` and adds any hosts not already in `remote-hosts.json`.

### Close a remote pane

```
/remote close my-server
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
  "my-server": {
    "host": "10.0.0.5",
    "user": "admin",
    "key": "~/.ssh/id_ed25519",
    "ssh_opts": "-o IdentitiesOnly=yes",
    "description": "Home server (LAN)"
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

## Development

### Testing

```bash
# Run all automated tests (requires bats)
./tests/run_tests.sh

# Or run bats directly
bats tests/
```

### Plugin Structure

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
│   ├── close.sh
│   ├── connect.sh
│   └── hosts.sh
├── tests/
│   ├── close.bats
│   ├── connect.bats
│   ├── hosts.bats
│   ├── run_tests.sh
│   └── test_helper.bash
├── LICENSE
└── README.md
```

## License

[MIT](LICENSE)
