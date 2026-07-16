# ABOUTME: Integration tests for connect.sh using an ephemeral tmux server.
# ABOUTME: Runs connect.sh in a private-socket session with a stubbed ssh binary.

load test_helper

setup() {
    mkdir -p "$TEST_TMP_DIR"
    echo '{}' > "$TEST_HOSTS_FILE"
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"

    # A stub ssh on PATH makes connections deterministic and offline.
    # Its behavior is read at runtime from $STUB_MODE_FILE: "ok" holds the
    # pane open at a prompt; "refused" prints an error and exits.
    STUB_BIN="${TEST_TMP_DIR}/bin"
    STUB_MODE_FILE="${TEST_TMP_DIR}/ssh_mode"
    mkdir -p "$STUB_BIN"
    echo "ok" > "$STUB_MODE_FILE"
    cat > "${STUB_BIN}/ssh" <<STUB
#!/usr/bin/env bash
echo "STUB-SSH-ARGS: \$*"
if [[ "\$(cat "$STUB_MODE_FILE" 2>/dev/null)" == "refused" ]]; then
    echo "ssh: connect to host failed: Connection refused"
    exit 255
fi
echo "STUB-CONNECTED"
exec bash --norc -i
STUB
    chmod +x "${STUB_BIN}/ssh"

    SOCKET="claude-tmux-it-$$-${BATS_TEST_NUMBER}"
    # Close fd 3 so the daemonized server doesn't hold bats' pipe open.
    tmux -L "$SOCKET" new-session -d -s it -x 200 -y 50 3>&-
    # Bake the stub dir into every new pane's PATH. tmux does not reliably
    # propagate its own PATH to split panes on macOS, and interactive login
    # shells reset it, so pin it here and start a no-rc shell.
    tmux -L "$SOCKET" set-option -g default-command "PATH=${STUB_BIN}:\$PATH exec bash --norc"
}

teardown() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TEST_TMP_DIR"
}

# Run connect.sh inside the test session and wait for it to finish.
# Sets CONNECT_OUTPUT and CONNECT_STATUS.
run_connect() {
    local target="$1"
    local out="${TEST_TMP_DIR}/connect_out"
    local exit_file="${TEST_TMP_DIR}/connect_exit"
    rm -f "$out" "$exit_file"

    tmux -L "$SOCKET" send-keys -t it \
        "bash ${SCRIPTS_DIR}/connect.sh ${TEST_HOSTS_FILE} ${target} > ${out} 2>&1; echo \$? > ${exit_file}" Enter

    for _ in $(seq 1 80); do
        [ -f "$exit_file" ] && break
        sleep 0.25
    done
    [ -f "$exit_file" ] || { echo "connect.sh did not finish"; return 1; }

    CONNECT_OUTPUT=$(cat "$out")
    CONNECT_STATUS=$(cat "$exit_file")
}

# Find the pane tagged @remote=<name>. Echoes the pane id, or returns 1.
find_tagged_pane() {
    local target="$1"
    for pane_id in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}'); do
        name=$(tmux -L "$SOCKET" show-options -p -t "$pane_id" -v @remote 2>/dev/null) || continue
        if [ "$name" = "$target" ]; then
            echo "$pane_id"
            return 0
        fi
    done
    return 1
}

@test "connect: saved host builds ssh command with port and tags pane" {
    create_sample_hosts
    run_connect "staging"

    [ "$CONNECT_STATUS" -eq 0 ]
    [[ "$CONNECT_OUTPUT" == *"deploy@staging.example.com"* ]]

    pane=$(find_tagged_pane "staging")
    [ -n "$pane" ]

    typed=$(tmux -L "$SOCKET" capture-pane -t "$pane" -p -S -)
    [[ "$typed" == *"ssh -t -p 2222 deploy@staging.example.com"* ]]
}

@test "connect: ad-hoc user@host creates tagged pane" {
    run_connect "root@203.0.113.7"

    [ "$CONNECT_STATUS" -eq 0 ]
    pane=$(find_tagged_pane "root@203.0.113.7")
    [ -n "$pane" ]

    typed=$(tmux -L "$SOCKET" capture-pane -t "$pane" -p -S -)
    [[ "$typed" == *"ssh -t root@203.0.113.7"* ]]
}

@test "connect: second connect to live pane reports existing connection" {
    create_sample_hosts
    run_connect "staging"
    [ "$CONNECT_STATUS" -eq 0 ]

    run_connect "staging"
    [ "$CONNECT_STATUS" -eq 0 ]
    [[ "$CONNECT_OUTPUT" == *"Already connected"* ]]

    # Still exactly one tagged pane
    count=0
    for pane_id in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id}'); do
        name=$(tmux -L "$SOCKET" show-options -p -t "$pane_id" -v @remote 2>/dev/null) || continue
        [ "$name" = "staging" ] && count=$((count + 1))
    done
    [ "$count" -eq 1 ]
}

@test "connect: unknown bare name fails with error" {
    run_connect "no-such-host"
    [ "$CONNECT_STATUS" -eq 1 ]
    [[ "$CONNECT_OUTPUT" == *"not a saved host name"* ]]
}

@test "connect: refused connection reports failure and cleans up pane" {
    echo "refused" > "$STUB_MODE_FILE"
    create_sample_hosts
    run_connect "staging"

    [ "$CONNECT_STATUS" -eq 1 ]
    [[ "$CONNECT_OUTPUT" == *"failed"* ]]

    run find_tagged_pane "staging"
    [ "$status" -ne 0 ]
}

@test "connect: key path expands tilde without executing embedded commands" {
    cat > "$TEST_HOSTS_FILE" <<HOSTS
{
  "sneaky": {
    "host": "203.0.113.9",
    "user": "admin",
    "key": "~/.ssh/key\$(touch ${TEST_TMP_DIR}/pwned)"
  }
}
HOSTS
    run_connect "sneaky"
    [ "$CONNECT_STATUS" -eq 0 ]

    # The command substitution must never execute; tilde must expand
    [ ! -f "${TEST_TMP_DIR}/pwned" ]

    pane=$(find_tagged_pane "sneaky")
    typed=$(tmux -L "$SOCKET" capture-pane -t "$pane" -p -S -)
    [[ "$typed" == *"${HOME}/.ssh/key"* ]]
}

@test "connect: key path with an embedded single quote cannot break out" {
    # A literal single quote in the key must not let the following
    # command substitution escape and execute in the pane shell.
    cat > "$TEST_HOSTS_FILE" <<HOSTS
{
  "evil": {
    "host": "203.0.113.10",
    "user": "admin",
    "key": "~/.ssh/key'\$(touch ${TEST_TMP_DIR}/pwned)'"
  }
}
HOSTS
    run_connect "evil"
    [ "$CONNECT_STATUS" -eq 0 ]

    [ ! -f "${TEST_TMP_DIR}/pwned" ]
}
