# ABOUTME: Tests for connect.sh argument validation and host resolution.
# ABOUTME: Skips tests requiring a live tmux session.

setup() {
    load test_helper
    # Unset TMUX so non-tmux error path is testable
    unset TMUX
}

@test "connect: no arguments prints usage and exits 1" {
    run bash "$SCRIPTS_DIR/connect.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "connect: one argument prints usage and exits 1" {
    run bash "$SCRIPTS_DIR/connect.sh" "$TEST_HOSTS_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "connect: outside tmux exits with error" {
    run bash "$SCRIPTS_DIR/connect.sh" "$TEST_HOSTS_FILE" "mac-mini"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Must be run inside a tmux session"* ]]
}
