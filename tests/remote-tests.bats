#!/usr/bin/env bats
# ABOUTME: Tests for remote-tests.sh, which runs a repo's suite on another machine
# ABOUTME: --print asserts the composed commands without touching the network

load test_helper

SCRIPT="${SCRIPTS_DIR}/remote-tests.sh"

@test "print: composes an rsync that excludes the private cs session dir" {
    local repo="${BATS_TEST_TMPDIR}/myproj"
    mkdir -p "$repo"

    run bash "$SCRIPT" --host alex@box --repo "$repo" --cmd 'make test' --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"rsync"* ]]
    [[ "$output" == *"alex@box"* ]]

    # Every repo this runs against is a cs session, so the narrative and memory
    # files sit in .cs/. Nothing in a test suite reads them and they should not
    # land on a second machine.
    [[ "$output" == *"--exclude .cs/"* ]]
}

@test "detect: finds tests/run_tests.sh when no --cmd is given" {
    local repo="${BATS_TEST_TMPDIR}/council-like"
    mkdir -p "$repo/tests"
    touch "$repo/tests/run_tests.sh"

    run bash "$SCRIPT" --host alex@box --repo "$repo" --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/run_tests.sh"* ]]
}

@test "detect: finds tests/run_all.sh, the other runner in use" {
    local repo="${BATS_TEST_TMPDIR}/cs-like"
    mkdir -p "$repo/tests"
    touch "$repo/tests/run_all.sh"

    run bash "$SCRIPT" --host alex@box --repo "$repo" --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/run_all.sh"* ]]
}

@test "detect: says what it looked for when it finds no runner" {
    local repo="${BATS_TEST_TMPDIR}/empty"
    mkdir -p "$repo"

    run bash "$SCRIPT" --host alex@box --repo "$repo" --print
    [ "$status" -ne 0 ]
    [[ "$output" == *"run_tests.sh"* ]]
    [[ "$output" == *"--cmd"* ]]
}

# Shim rsync and ssh so the execution path is exercised without a network.
# Quoted heredoc on purpose: $@ must be expanded by the shim at run time, not
# by this shell at write time.
install_shims() {
    SHIM_BIN="${BATS_TEST_TMPDIR}/bin"
    SHIM_LOG="${BATS_TEST_TMPDIR}/calls.log"
    mkdir -p "$SHIM_BIN"
    : > "$SHIM_LOG"
    for tool in rsync ssh; do
        cat > "$SHIM_BIN/$tool" <<EOF
#!/bin/bash
printf '%s\n' "$tool" >> "$SHIM_LOG"
printf '  ARG:%s\n' "\$@" >> "$SHIM_LOG"
exit 0
EOF
        chmod +x "$SHIM_BIN/$tool"
    done
}

@test "run: syncs then launches the suite detached and names the log" {
    install_shims
    local repo="${BATS_TEST_TMPDIR}/proj"
    mkdir -p "$repo/tests"
    touch "$repo/tests/run_tests.sh"

    PATH="$SHIM_BIN:$PATH" run bash "$SCRIPT" --host alex@box --repo "$repo"
    [ "$status" -eq 0 ]

    # Sync must happen before the run, or the suite tests the previous copy.
    local rsync_line ssh_line
    rsync_line=$(grep -n '^rsync$' "$SHIM_LOG" | head -1 | cut -d: -f1)
    ssh_line=$(grep -n '^ssh$' "$SHIM_LOG" | tail -1 | cut -d: -f1)
    [ -n "$rsync_line" ]
    [ -n "$ssh_line" ]
    [ "$rsync_line" -lt "$ssh_line" ]

    # The caller needs a way back to the output of a detached run.
    [[ "$output" == *"suite.log"* ]]
}

@test "run: a repo path containing spaces reaches rsync as one argument" {
    install_shims
    local repo="${BATS_TEST_TMPDIR}/my proj"
    mkdir -p "$repo/tests"
    touch "$repo/tests/run_tests.sh"

    PATH="$SHIM_BIN:$PATH" run bash "$SCRIPT" --host alex@box --repo "$repo"
    [ "$status" -eq 0 ]

    # Word-splitting a command held in a string turns "/tmp/my proj/" into two
    # arguments, and rsync then copies a directory that does not exist. The shim
    # logs one ARG: line per argument, so a split is visible as a bare "ARG:my".
    grep -q "ARG:.*my proj/" "$SHIM_LOG"
    ! grep -qx "  ARG:my" "$SHIM_LOG"
}

@test "run: records the suite's real exit status, not a TAP-shaped guess" {
    install_shims
    local repo="${BATS_TEST_TMPDIR}/proj"
    mkdir -p "$repo/tests"
    touch "$repo/tests/run_tests.sh"

    PATH="$SHIM_BIN:$PATH" run bash "$SCRIPT" --host alex@box --repo "$repo"
    [ "$status" -eq 0 ]

    # Counting "^not ok" only works for TAP. cs's runner prints its own summary,
    # so that grep returns 0 whether the suite passed or failed — a silent green.
    # The exit code is the one signal every runner produces.
    grep -q "suite.status" "$SHIM_LOG"
    [[ "$output" == *"suite.status"* ]]
    [[ "$output" != *'grep -c "^not ok"'* ]]
}

@test "host: a saved name resolves to user@host from the store" {
    create_sample_hosts
    local repo="${BATS_TEST_TMPDIR}/proj"
    mkdir -p "$repo/tests"; touch "$repo/tests/run_tests.sh"

    run bash "$SCRIPT" --host mac-mini --hosts-file "$TEST_HOSTS_FILE" \
        --repo "$repo" --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"hex@192.168.1.98"* ]]
}

@test "host: a literal user@host is used as given, not looked up" {
    create_sample_hosts
    local repo="${BATS_TEST_TMPDIR}/proj"
    mkdir -p "$repo/tests"; touch "$repo/tests/run_tests.sh"

    run bash "$SCRIPT" --host alex@box --hosts-file "$TEST_HOSTS_FILE" \
        --repo "$repo" --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"alex@box"* ]]
}

@test "host: an unknown name says how to add it rather than guessing" {
    create_sample_hosts
    local repo="${BATS_TEST_TMPDIR}/proj"
    mkdir -p "$repo/tests"; touch "$repo/tests/run_tests.sh"

    run bash "$SCRIPT" --host nosuchbox --hosts-file "$TEST_HOSTS_FILE" \
        --repo "$repo" --print
    [ "$status" -ne 0 ]
    [[ "$output" == *"nosuchbox"* ]]
    [[ "$output" == *"/remote add"* ]]
}

@test "host: a saved key and ssh_opts reach both rsync and ssh" {
    create_sample_hosts
    local repo="${BATS_TEST_TMPDIR}/proj"
    mkdir -p "$repo/tests"; touch "$repo/tests/run_tests.sh"

    run bash "$SCRIPT" --host mac-mini --hosts-file "$TEST_HOSTS_FILE" \
        --repo "$repo" --print
    [ "$status" -eq 0 ]

    # The store records these because the connection needs them. rsync tunnels
    # over its own ssh, so dropping them there fails while ssh alone succeeds.
    [[ "$output" == *"IdentitiesOnly=yes"* ]]
    [[ "$output" == *"id_ed25519"* ]]

    local rsync_line
    rsync_line=$(echo "$output" | grep '^rsync ')
    [[ "$rsync_line" == *"IdentitiesOnly=yes"* ]]
}
