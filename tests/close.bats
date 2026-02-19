# ABOUTME: Tests for close.sh argument validation.
# ABOUTME: Skips tests requiring a live tmux session.

setup() {
    load test_helper
    unset TMUX
}

@test "close: no arguments prints usage and exits 1" {
    run bash "$SCRIPTS_DIR/close.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "close: outside tmux exits with error" {
    run bash "$SCRIPTS_DIR/close.sh" "mac-mini"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Must be run inside a tmux session"* ]]
}
