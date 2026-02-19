# ABOUTME: Tests for hosts.sh host management operations.
# ABOUTME: Covers list, add, remove, get, and import-ssh subcommands.

setup() {
    load test_helper
}

# --- Usage and argument validation ---

@test "hosts: no arguments prints usage and exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "hosts: only hosts file arg prints usage and exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "hosts: unknown subcommand exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" "bogus"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown subcommand"* ]]
}

# --- list ---

@test "hosts list: empty file shows no saved hosts" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No saved hosts"* ]]
}

@test "hosts list: shows saved hosts with columns" {
    create_sample_hosts
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"mac-mini"* ]]
    [[ "$output" == *"hex@192.168.1.98"* ]]
    [[ "$output" == *"staging"* ]]
    [[ "$output" == *"deploy@staging.example.com"* ]]
}

# --- add ---

@test "hosts add: missing args exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" add
    [ "$status" -eq 1 ]
}

@test "hosts add: missing user@host exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" add "myhost"
    [ "$status" -eq 1 ]
}

@test "hosts add: invalid format (no @) exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" add "myhost" "not-userhost"
    [ "$status" -eq 1 ]
    [[ "$output" == *"user@host format"* ]]
}

@test "hosts add: creates a new host entry" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" add "web" "root@web.example.com" "Web server"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added host 'web'"* ]]

    local json
    json=$(cat "$TEST_HOSTS_FILE")
    assert_json_eq "$json" '.web.user' "root"
    assert_json_eq "$json" '.web.host' "web.example.com"
    assert_json_eq "$json" '.web.description' "Web server"
}

@test "hosts add: rejects duplicate name" {
    bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" add "web" "root@web.example.com"
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" add "web" "other@other.com"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "hosts add: without description stores empty string" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" add "bare" "user@host.com"
    [ "$status" -eq 0 ]

    local json
    json=$(cat "$TEST_HOSTS_FILE")
    assert_json_eq "$json" '.bare.description' ""
}

# --- remove ---

@test "hosts remove: missing name exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" remove
    [ "$status" -eq 1 ]
}

@test "hosts remove: nonexistent host exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" remove "ghost"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "hosts remove: deletes an existing host" {
    create_sample_hosts
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" remove "staging"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed host 'staging'"* ]]

    # Verify it's gone
    run jq -e '.staging' "$TEST_HOSTS_FILE"
    [ "$status" -ne 0 ]
}

@test "hosts remove: leaves other hosts intact" {
    create_sample_hosts
    bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" remove "staging"

    local json
    json=$(cat "$TEST_HOSTS_FILE")
    assert_json_has "$json" '.["mac-mini"]'
    assert_json_eq "$json" '.["mac-mini"].host' "192.168.1.98"
}

# --- get ---

@test "hosts get: missing name exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" get
    [ "$status" -eq 1 ]
}

@test "hosts get: nonexistent host exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" get "ghost"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "hosts get: prints full JSON for a host" {
    create_sample_hosts
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" get "mac-mini"
    [ "$status" -eq 0 ]

    assert_json_eq "$output" '.host' "192.168.1.98"
    assert_json_eq "$output" '.user' "hex"
    assert_json_eq "$output" '.key' "~/.ssh/id_ed25519"
}

# --- import-ssh ---

@test "hosts import-ssh: missing SSH config exits 1" {
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" import-ssh "/nonexistent/path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SSH config not found"* ]]
}

@test "hosts import-ssh: imports hosts from SSH config" {
    create_ssh_config
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" import-ssh "${TEST_TMP_DIR}/ssh_config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"added: dev-box"* ]]
    [[ "$output" == *"added: ci-runner"* ]]
    [[ "$output" == *"Imported 2"* ]]

    local json
    json=$(cat "$TEST_HOSTS_FILE")
    assert_json_eq "$json" '.["dev-box"].host' "10.0.0.5"
    assert_json_eq "$json" '.["dev-box"].user' "admin"
    assert_json_eq "$json" '.["ci-runner"].host' "ci.internal.net"
    assert_json_eq "$json" '.["ci-runner"].user' "ci"
}

@test "hosts import-ssh: skips wildcard hosts" {
    create_ssh_config
    bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" import-ssh "${TEST_TMP_DIR}/ssh_config"

    # *.example.com should not be imported
    run jq -e '.["*.example.com"]' "$TEST_HOSTS_FILE"
    [ "$status" -ne 0 ]
}

@test "hosts import-ssh: skips already-existing hosts" {
    create_ssh_config
    # Pre-add dev-box
    bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" add "dev-box" "other@other.com"
    run bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" import-ssh "${TEST_TMP_DIR}/ssh_config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip: dev-box"* ]]
    [[ "$output" == *"skipped 1"* ]]

    # Original should be preserved, not overwritten
    local json
    json=$(cat "$TEST_HOSTS_FILE")
    assert_json_eq "$json" '.["dev-box"].host' "other.com"
}

@test "hosts import-ssh: imports SSH key when present" {
    create_ssh_config
    bash "$SCRIPTS_DIR/hosts.sh" "$TEST_HOSTS_FILE" import-ssh "${TEST_TMP_DIR}/ssh_config"

    local json
    json=$(cat "$TEST_HOSTS_FILE")
    assert_json_eq "$json" '.["dev-box"].key' "~/.ssh/dev_key"
}

# --- Auto-create hosts file ---

@test "hosts: creates hosts file if it doesn't exist" {
    local new_file="${TEST_TMP_DIR}/new-hosts.json"
    rm -f "$new_file"
    run bash "$SCRIPTS_DIR/hosts.sh" "$new_file" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No saved hosts"* ]]
    [ -f "$new_file" ]
}
