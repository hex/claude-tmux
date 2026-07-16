# ABOUTME: Integration tests for connect.sh using an ephemeral tmux server.
# ABOUTME: Runs connect.sh inside a private-socket tmux session and inspects panes.

load test_helper

setup() {
    mkdir -p "$TEST_TMP_DIR"
    echo '{}' > "$TEST_HOSTS_FILE"
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"

    SOCKET="claude-tmux-it-$$-${BATS_TEST_NUMBER}"
    # Close fd 3 so the daemonized tmux server doesn't hold bats' pipe open
    tmux -L "$SOCKET" new-session -d -s it -x 200 -y 50 3>&-
}

teardown() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TEST_TMP_DIR"
}

# Run connect.sh inside the test tmux session and wait for it to finish.
# Sets CONNECT_OUTPUT and CONNECT_STATUS.
run_connect() {
    local target="$1"
    local out="${TEST_TMP_DIR}/connect_out"
    local exit_file="${TEST_TMP_DIR}/connect_exit"
    rm -f "$out" "$exit_file"

    tmux -L "$SOCKET" send-keys -t it \
        "bash ${SCRIPTS_DIR}/connect.sh ${TEST_HOSTS_FILE} ${target} > ${out} 2>&1; echo \$? > ${exit_file}" Enter

    for _ in $(seq 1 60); do
        [ -f "$exit_file" ] && break
        sleep 0.25
    done
    [ -f "$exit_file" ] || { echo "connect.sh did not finish"; return 1; }

    CONNECT_OUTPUT=$(cat "$out")
    CONNECT_STATUS=$(cat "$exit_file")
}

# Find the pane tagged @remote=<name> on the test server.
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

@test "connect: saved host builds ssh command with port, opts, and tags pane" {
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

@test "connect: key path expands tilde without executing embedded commands" {
    # Port 1 on localhost refuses fast, proving the pane shell ran the command
    cat > "$TEST_HOSTS_FILE" <<HOSTS
{
  "sneaky": {
    "host": "127.0.0.1",
    "port": 1,
    "user": "admin",
    "ssh_opts": "-o ConnectTimeout=2 -o StrictHostKeyChecking=no",
    "key": "~/.ssh/key\$(touch ${TEST_TMP_DIR}/pwned)"
  }
}
HOSTS
    run_connect "sneaky"

    pane=$(find_tagged_pane "sneaky")
    [ -n "$pane" ]

    # Wait until ssh has run and failed, so the shell has fully
    # evaluated the command line before we assert nothing leaked
    executed=""
    for _ in $(seq 1 40); do
        typed=$(tmux -L "$SOCKET" capture-pane -t "$pane" -p -S -)
        if [[ "$typed" == *"refused"* || "$typed" == *"ssh:"* ]]; then
            executed=1
            break
        fi
        sleep 0.25
    done
    [ -n "$executed" ]

    # The command substitution must never execute, tilde must expand
    [ ! -f "${TEST_TMP_DIR}/pwned" ]
    [[ "$typed" == *"-i '${HOME}/.ssh/key"* ]]
}
