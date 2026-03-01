---
name: Remote SSH via tmux
description: This skill should be used when the user asks to "run commands on a remote pane", "check remote pane output", "capture output from remote", "send commands to remote server", "tail logs on prod", "check disk space on staging", "run uptime across servers", "is my SSH connection alive", "read what's on the remote pane", or needs to interact with already-established SSH connections in tmux panes. Also activates when you are about to suggest the user manually SSH into a remote host to run a command, when a command needs to run on a remote machine, when troubleshooting requires executing something on a known remote host, or when you would otherwise tell the user to "run this on the server" or "SSH in and do X". Not for creating new connections (use the /remote command for that).
version: 2026.2.2
---
<!-- ABOUTME: Skill definition for interacting with remote hosts via SSH-over-tmux. -->
<!-- ABOUTME: Covers sending commands, capturing output, connection management, and common workflows. -->

# Remote SSH via tmux

## Overview

The claude-tmux plugin manages SSH connections via tmux panes. This skill documents patterns for interacting with those connections. Each remote connection lives in a dedicated tmux pane, tagged with a custom `@remote` option set to the connection name (e.g., `mac-mini`, `prod-web`). The `/remote` command handles establishing connections; this skill covers the patterns for interacting with those connections once established.

All remote interaction follows a consistent model: find the target pane by its `@remote` tag, send commands using `tmux send-keys`, and read output using `tmux capture-pane`.

## Proactive Remote Execution

**When you determine that a command needs to run on a remote host -- instead of telling the user to SSH in and run it manually -- check for an active remote pane first.**

### Detection

Before suggesting manual SSH commands, check if a remote pane is connected to the target host:

```bash
for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
  name=$(tmux show-options -p -t "$pane_id" -v @remote 2>/dev/null) && [ -n "$name" ] && echo "$pane_id $name"
done
```

Also check saved hosts to see if the target machine has a known entry:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/hosts.sh ${CLAUDE_PLUGIN_ROOT}/remote-hosts.json list
```

### Offering Remote Execution

If an active pane exists for the target host, use **AskUserQuestion** to offer running the command through it:

- Question: "This command needs to run on `<host>`. Want me to run it through the remote pane, or would you prefer to do it manually?"
- Header: "Remote exec"
- Options:
  - **Run via remote pane** -- "Send the command through the connected tmux pane"
  - **Show command only** -- "Display the command for manual execution"

If no pane is connected but the host is saved, offer to connect first:

- Question: "This command needs to run on `<host>`. Want me to connect and run it?"
- Header: "Remote exec"
- Options:
  - **Connect and run** -- "Open a remote pane to `<host>` and send the command"
  - **Show command only** -- "Display the command for manual execution"

### Commands Requiring sudo or TTY

tmux panes have a real TTY, so sudo and interactive commands work through them. For sudo commands, send the command normally -- the remote pane's TTY handles password prompts. Use prompt detection (not marker polling) to wait for sudo's password prompt or completion:

```bash
tmux send-keys -t "$PANE" "sudo systemctl restart nginx" Enter
```

After sending a sudo command, capture the pane output to check whether it's waiting for a password. If it is, inform the user so they can type the password in the pane directly.

### When NOT to Offer

Do not offer remote execution when:
- The user explicitly asked for the command text (e.g., "what command would I run to...")
- The command involves sensitive credentials that shouldn't pass through send-keys
- There is no tmux session available (`$TMUX` is unset)

## Sending Commands to Remote Panes

### Find the Target Pane

Remote panes are tagged with the `@remote` custom pane option. List all remote panes:

```bash
for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
  name=$(tmux show-options -p -t "$pane_id" -v @remote 2>/dev/null) && [ -n "$name" ] && echo "$pane_id $name"
done
```

To find a specific named remote pane:

```bash
for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
  name=$(tmux show-options -p -t "$pane_id" -v @remote 2>/dev/null) && [ "$name" = "prod-web" ] && echo "$pane_id"
done
```

### Send a Single Command

```bash
tmux send-keys -t <pane_id> "<command>" Enter
```

The `Enter` argument (unquoted) sends a keypress to execute the command. Without it, the text appears in the pane but does not execute.

### Send Multiple Commands Sequentially

Send commands one at a time with a brief pause between them to allow each to begin executing:

```bash
tmux send-keys -t %5 "cd /var/log" Enter
sleep 0.5
tmux send-keys -t %5 "tail -n 50 syslog" Enter
```

### Handle Special Characters

Escape double quotes and dollar signs within the command string:

```bash
tmux send-keys -t %5 "echo \"hello world\"" Enter
tmux send-keys -t %5 "echo \$HOME" Enter
```

For commands with complex quoting, use single quotes in the outer layer:

```bash
tmux send-keys -t %5 'grep "error" /var/log/app.log | wc -l' Enter
```

### Wait for Command Completion

After sending a command, wait for it to finish before capturing output. Prefer the marker-polling pattern over fixed sleeps -- it adapts to actual command duration instead of guessing.

**Marker polling (preferred):** Append a unique marker after the command, then poll until it appears:

```bash
MARKER="__DONE_$$_$(date +%s)__"
tmux send-keys -t %5 "ls -la /etc; echo ${MARKER}" Enter
for i in $(seq 1 30); do
  sleep 0.5
  tmux capture-pane -t %5 -p -S -50 | grep -q "$MARKER" && break
done
tmux capture-pane -t %5 -p -S -50
```

The marker is unique per invocation (PID + timestamp), so it won't collide with command output. The loop polls every 0.5s for up to 15 seconds.

**Prompt detection (when markers aren't possible):** For commands already in flight, interactive programs, or REPLs where appending a marker would change behavior, poll for the shell prompt to reappear:

```bash
# Snapshot the prompt before sending
PROMPT_CHAR=$(tmux capture-pane -t %5 -p | grep -v '^$' | tail -1 | grep -oE '[#$%>❯] *$')
tmux send-keys -t %5 "long-running-command" Enter
for i in $(seq 1 60); do
  sleep 0.5
  LAST=$(tmux capture-pane -t %5 -p | grep -v '^$' | tail -1)
  echo "$LAST" | grep -qE '[#$%>❯] *$' && break
done
tmux capture-pane -t %5 -p -S -50
```

This works by detecting when a prompt-ending character (`$`, `#`, `%`, `>`, `❯`) appears at the end of the last non-empty line -- meaning the shell is waiting for input again. Use this when you cannot modify the command string.

**Fixed delay (simple commands only):** For commands that reliably complete within a known time:

```bash
tmux send-keys -t %5 "uptime" Enter
sleep 1
```

Use fixed delays only for trivial commands (uptime, whoami, pwd). For anything that touches disk, network, or processes, use marker polling or prompt detection.

## Capturing Remote Output

### Capture Visible Pane Contents

Print the current visible contents of a remote pane to stdout:

```bash
tmux capture-pane -t <pane_id> -p
```

### Capture Recent Lines

Retrieve the last N lines of output (including scrollback beyond the visible area):

```bash
tmux capture-pane -t <pane_id> -p -S -20
```

The `-S -20` flag starts capture 20 lines before the current bottom of the pane.

### Capture Entire Scrollback

Retrieve all available scrollback history:

```bash
tmux capture-pane -t <pane_id> -p -S -
```

The `-S -` flag starts from the very beginning of the scrollback buffer.

### Save Output to File

Redirect captured output to a local file for processing:

```bash
tmux capture-pane -t <pane_id> -p > /tmp/remote-output.txt
```

### Capture and Search

Combine capture with grep to find specific output:

```bash
tmux capture-pane -t %5 -p -S - | grep "ERROR"
```


## Connection Management

### Check Pane Health

Determine whether a remote pane is still alive:

```bash
tmux list-panes -a -F '#{pane_id} #{pane_title} #{pane_dead}'
```

A value of `1` in the `pane_dead` column indicates the pane's process has exited (SSH session terminated or crashed).

### List All Remote Panes

Iterate panes and check for the `@remote` tag:

```bash
for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
  name=$(tmux show-options -p -t "$pane_id" -v @remote 2>/dev/null) && [ -n "$name" ] && \
    dead=$(tmux display-message -t "$pane_id" -p '#{pane_dead}') && echo "$pane_id $name dead=$dead"
done
```

### Close a Remote Pane

Terminate a remote connection by killing its pane:

```bash
tmux kill-pane -t <pane_id>
```

To gracefully disconnect first, send an `exit` command before killing:

```bash
tmux send-keys -t %5 "exit" Enter
sleep 1
tmux kill-pane -t %5
```

### Reconnect a Dropped Session

If an SSH connection drops (pane still alive but shell returned to local), send the SSH command again to the same pane:

```bash
tmux send-keys -t %5 "ssh user@host" Enter
```

If the pane is dead, create a new connection using the plugin's connect script. The plugin prefers Eternal Terminal (`et`) over SSH when available, which survives network changes automatically and rarely drops.

Never use mosh for remote tmux pane connections — it is not designed for tunneling traffic and will cause reliability issues.

### Detect Connection State

Check whether the remote pane is at a remote shell or has fallen back to a local shell by inspecting the pane output:

```bash
tmux capture-pane -t %5 -p -S -3
```

Look for the remote hostname in the prompt to confirm the SSH session is active.

## Common Workflows

### Run a Command and Capture Output

The most frequent pattern -- execute a remote command and retrieve the result:

```bash
PANE=$(for p in $(tmux list-panes -a -F '#{pane_id}'); do n=$(tmux show-options -p -t "$p" -v @remote 2>/dev/null) && [ "$n" = "prod-web" ] && echo "$p"; done)
MARKER="__DONE_$$_$(date +%s)__"
tmux send-keys -t "$PANE" "df -h; echo ${MARKER}" Enter
for i in $(seq 1 30); do sleep 0.5; tmux capture-pane -t "$PANE" -p -S -50 | grep -q "$MARKER" && break; done
tmux capture-pane -t "$PANE" -p -S -50
```

### Detect Remote Command Errors

Check whether a remote command succeeded by appending an exit code marker:

```bash
MARKER="__EXIT_$$_$(date +%s)__"
tmux send-keys -t "$PANE" "some-command && echo ${MARKER}:0 || echo ${MARKER}:1" Enter
for i in $(seq 1 30); do sleep 0.5; tmux capture-pane -t "$PANE" -p -S -20 | grep -q "$MARKER" && break; done
tmux capture-pane -t "$PANE" -p -S -20 | grep "$MARKER"
```

A result ending in `:0` indicates success; `:1` indicates failure. The unique marker prevents collisions with command output.

### File Transfer

Use scp or rsync from a **local** pane (not the remote pane) to transfer files:

```bash
scp user@host:/path/to/remote/file /tmp/local-copy
rsync -avz user@host:/var/log/app/ /tmp/remote-logs/
```

Do not attempt file transfers through `send-keys` on a remote pane -- use a separate local command.

### Port Forwarding

Include the `-L` flag in the SSH command when establishing the connection:

```bash
ssh -L 8080:localhost:3000 user@host
```

This forwards local port 8080 to port 3000 on the remote host. Set this up during connection creation, not after the session is established.

### Interactive Sessions

`send-keys` handles interactive CLI tools running on the remote host. Send keystrokes as individual arguments:

```bash
# Open a file in vim
tmux send-keys -t %5 "vim /etc/nginx/nginx.conf" Enter

# Type in insert mode
tmux send-keys -t %5 "i" "new content" Escape

# Save and quit
tmux send-keys -t %5 ":wq" Enter
```

For Python/Node REPL sessions:

```bash
tmux send-keys -t %5 "python3" Enter
sleep 1
tmux send-keys -t %5 "import os; print(os.uname())" Enter
```

### Long-Running Commands

For jobs that run for minutes or longer (backups, migrations, batch processing), redirect output to a log file on the remote host so progress is checkable without keeping the shell blocked:

```bash
tmux send-keys -t "$PANE" "nohup /opt/backup.sh > /tmp/backup.log 2>&1 &" Enter
```

Check progress later:

```bash
tmux send-keys -t "$PANE" "tail -5 /tmp/backup.log" Enter
```

Check if the job is still running:

```bash
tmux send-keys -t "$PANE" "jobs -l" Enter
```

This keeps the remote shell available for other commands while the job runs in the background.

### Multi-Host Operations

Run the same command across multiple remote panes:

```bash
# Collect remote pane IDs
REMOTE_PANES=()
for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
  name=$(tmux show-options -p -t "$pane_id" -v @remote 2>/dev/null) && [ -n "$name" ] && REMOTE_PANES+=("$pane_id")
done

# Send command to all with a shared marker
MARKER="__DONE_$$_$(date +%s)__"
for pane in "${REMOTE_PANES[@]}"; do
  tmux send-keys -t "$pane" "uptime; echo ${MARKER}" Enter
done

# Wait for all panes to complete, then capture
for pane in "${REMOTE_PANES[@]}"; do
  for i in $(seq 1 20); do sleep 0.5; tmux capture-pane -t "$pane" -p -S -20 | grep -q "$MARKER" && break; done
  echo "=== $pane ==="
  tmux capture-pane -t "$pane" -p -S -5
done
```

### Multi-Step Remote Workflows

When executing a sequence of remote commands (deployments, migrations, diagnostics), use TodoWrite to track progress through each step. This prevents losing track of where you are if a step fails or the conversation is interrupted.

Pattern:
1. Create todos for each step before starting
2. Mark each in-progress as you execute it
3. Capture and verify output before marking complete
4. If a step fails, leave it in-progress and report the error

Example -- deploying to a remote host:
1. TodoWrite: create tasks for health check, deploy, verify
2. For each task: send the command via `send-keys`, poll for completion with marker, capture output, check for errors, mark todo complete
3. If any step fails (marker shows `:1`), stop and report which step failed with the captured output

This pattern is especially valuable for multi-host operations where you run the same sequence on several hosts -- track each host's progress independently.

## Plugin Scripts

The plugin provides helper scripts for connection and host management:

- **`${CLAUDE_PLUGIN_ROOT}/scripts/connect.sh`** -- Create new SSH connections in tmux panes. Prefers `et` over `ssh` when available. Supports a `command` field in host config to run a command on connect (e.g., `tmux new -A -s main` to attach to a persistent remote tmux session). Uses `et -c` or `ssh -t` accordingly.
- **`${CLAUDE_PLUGIN_ROOT}/scripts/hosts.sh`** -- Manage saved remote host configurations. Add, remove, and list known hosts.
- **`${CLAUDE_PLUGIN_ROOT}/remote-hosts.json`** -- Persistent storage for saved host entries (hostname, user, port, identity file, and custom options).

Use these scripts rather than manually constructing tmux and SSH commands when creating new connections. For interacting with already-established connections, use the `send-keys` and `capture-pane` patterns described above.
