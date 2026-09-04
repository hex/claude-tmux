# claude-tmux

Connect to remote hosts via SSH in tmux panes. Manage saved hosts, open ad-hoc connections, and interact with remote sessions from Claude Code.

## Features

- **Saved host management** -- add, remove, list, and connect to named hosts from a JSON config
- **Ad-hoc connections** -- connect to any `user@host` without saving it first
- **Idempotent connections** -- reconnects dead panes, reuses live ones
- **SSH config import** -- bulk-import hosts from `~/.ssh/config`
- **Eternal Terminal support** -- opt-in `et` for hosts that benefit from persistent connections
- **Pane health monitoring** -- check which remote panes are alive or dead
- **Graceful disconnect** -- sends `exit` before killing panes
- **Remote test runs** -- sync a repo to a saved host and run its suite there, detached

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
- [Eternal Terminal](https://eternalterminal.dev/) (optional) -- used when a host has `"use_et": true`

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

### Remove a saved host

```
/remote remove staging
```

Deletes the host from `remote-hosts.json`. Does not close an active pane for it.

### Import from SSH config

```
/remote import-ssh
```

Parses `~/.ssh/config` and adds any hosts not already in `remote-hosts.json`. Imports `HostName`, `User`, `IdentityFile`, and `Port`; multi-name `Host` lines and wildcard aliases are handled (each concrete name imported, wildcards skipped).

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
- `use_et` (optional) -- set to `true` to use Eternal Terminal instead of SSH
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

## Remote Test Runs

A suite that takes minutes locally competes with everything else on the machine.
`remote-tests.sh` copies the repo to a saved host, starts the suite there
detached, and hands back the commands to follow it:

```bash
# From inside the repo, using a host saved by /remote
bash scripts/remote-tests.sh --host mac-mini

# Or a literal target, with the commands printed and nothing run
bash scripts/remote-tests.sh --host user@box --print
```

The runner is detected (`tests/run_tests.sh`, then `tests/run_all.sh`) unless
`--cmd` overrides it. A host name without an `@` is resolved from the same store
`/remote` maintains, and its saved `key` and `ssh_opts` are passed to both ssh
and rsync -- rsync tunnels over its own ssh, so omitting them there fails while
a plain ssh to the same host succeeds.

`.cs/` is excluded by default; `.git` is kept, because suites that shell out to
git fail confusingly without it. The verdict is the exit code left in
`suite.status`, not a count of TAP lines -- a runner that prints its own summary
yields zero of those whether it passed or failed.

The **Remote test runs** skill activates when a full suite is about to run and
would take minutes, or when asked to run tests on another machine. It stays out
of the way for a single file or a `--changed` run, where syncing costs more than
it saves.

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
├── .github/
│   └── workflows/
│       └── ci.yml
├── commands/
│   └── remote.md
├── skills/
│   ├── remote/
│   │   └── SKILL.md
│   └── remote-tests/
│       └── SKILL.md
├── scripts/
│   ├── close.sh
│   ├── connect.sh
│   ├── hosts.sh
│   └── remote-tests.sh
├── tests/
│   ├── close.bats
│   ├── connect.bats
│   ├── connect_integration.bats
│   ├── hosts.bats
│   ├── remote-tests.bats
│   ├── run_tests.sh
│   └── test_helper.bash
├── LICENSE
└── README.md
```

## License

[MIT](LICENSE)
