#!/bin/bash
# ABOUTME: Test runner script for claude-tmux.
# ABOUTME: Runs all bats tests with optional filtering.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats >/dev/null 2>&1; then
    echo "Error: bats not found"
    echo ""
    echo "Install bats-core:"
    echo "  macOS:  brew install bats-core"
    echo "  Ubuntu: sudo apt install bats"
    echo "  Manual: https://github.com/bats-core/bats-core#installation"
    exit 1
fi

TEST_FILES="${1:-${SCRIPT_DIR}/*.bats}"

echo "Running tests..."
echo "================"
echo ""

if [[ -t 1 ]]; then
    bats --pretty $TEST_FILES
else
    bats --tap $TEST_FILES
fi
