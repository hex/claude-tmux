# ABOUTME: Common test utilities and setup for bats tests.
# ABOUTME: Sourced by all test files to provide shared fixtures and helpers.

export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"

# Test-specific directories
export TEST_TMP_DIR="${BATS_TEST_TMPDIR:-/tmp/claude-tmux-tests}"
export TEST_HOSTS_FILE="${TEST_TMP_DIR}/hosts.json"

setup() {
    mkdir -p "$TEST_TMP_DIR"
    echo '{}' > "$TEST_HOSTS_FILE"
}

teardown() {
    rm -rf "$TEST_TMP_DIR"
}

# Helper: create a hosts.json with a sample entry
create_sample_hosts() {
    cat > "$TEST_HOSTS_FILE" <<'HOSTS'
{
  "mac-mini": {
    "host": "192.168.1.98",
    "user": "hex",
    "key": "~/.ssh/id_ed25519",
    "ssh_opts": "-o IdentitiesOnly=yes",
    "description": "Mac Mini (wired LAN)"
  },
  "staging": {
    "host": "staging.example.com",
    "user": "deploy",
    "port": 2222,
    "description": "Staging server"
  }
}
HOSTS
}

# Helper: create a minimal SSH config for import tests
create_ssh_config() {
    cat > "${TEST_TMP_DIR}/ssh_config" <<'SSHCFG'
Host dev-box
    HostName 10.0.0.5
    User admin
    IdentityFile ~/.ssh/dev_key

Host *.example.com
    User deploy

Host ci-runner
    HostName ci.internal.net
    User ci
SSHCFG
}

# Helper: assert JSON field equals value
assert_json_eq() {
    local json="$1"
    local path="$2"
    local expected="$3"
    local actual
    actual=$(echo "$json" | jq -r "$path")
    if [[ "$actual" != "$expected" ]]; then
        echo "JSON assertion failed: $path"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        return 1
    fi
}

# Helper: assert JSON field exists
assert_json_has() {
    local json="$1"
    local path="$2"
    if ! echo "$json" | jq -e "$path" >/dev/null 2>&1; then
        echo "JSON field missing: $path"
        return 1
    fi
}
