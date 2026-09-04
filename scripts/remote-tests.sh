#!/bin/bash
# ABOUTME: Copies a repo to another machine over ssh and runs its test suite there
# ABOUTME: Takes an explicit --host: ssh config is not readable and is not guessed

set -euo pipefail

usage() {
    cat >&2 << 'EOF'
Usage: run.sh --host user@host [OPTIONS]

Options:
  --host NAME        A host saved by /remote, or a literal user@host
  --hosts-file PATH  Host store (default: the plugin's remote-hosts.json)
  --repo DIR         Repo to copy (default: current directory)
  --cmd CMD          Test command to run there (required)
  --remote-dir DIR   Where to put it (default: ci/<repo basename>)
  --exclude PATTERN  Extra rsync exclude; repeatable
  --print            Print the commands and exit, running nothing
  --help, -h         This message
EOF
    exit 1
}

HOST=""
REPO=""
CMD=""
REMOTE_DIR=""
EXTRA_EXCLUDES=""
HOSTS_FILE=""
SSH_OPTS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --host=*)        HOST="${1#*=}"; shift ;;
        --host)          HOST="${2:-}"; shift 2 ;;
        --repo=*)        REPO="${1#*=}"; shift ;;
        --repo)          REPO="${2:-}"; shift 2 ;;
        --cmd=*)         CMD="${1#*=}"; shift ;;
        --cmd)           CMD="${2:-}"; shift 2 ;;
        --remote-dir=*)  REMOTE_DIR="${1#*=}"; shift ;;
        --remote-dir)    REMOTE_DIR="${2:-}"; shift 2 ;;
        --hosts-file=*)  HOSTS_FILE="${1#*=}"; shift ;;
        --hosts-file)    HOSTS_FILE="${2:-}"; shift 2 ;;
        --exclude=*)     EXTRA_EXCLUDES="$EXTRA_EXCLUDES ${1#*=}"; shift ;;
        --exclude)       EXTRA_EXCLUDES="$EXTRA_EXCLUDES ${2:-}"; shift 2 ;;
        --print)         PRINT_ONLY=1; shift ;;
        --help|-h)       usage ;;
        -*)              echo "Error: Unknown flag: $1" >&2; usage ;;
        *)               echo "Error: Unexpected argument: $1" >&2; usage ;;
    esac
done

PRINT_ONLY="${PRINT_ONLY:-0}"

if [[ -z "$HOST" ]]; then
    echo "Error: --host is required." >&2
    usage
fi

# A name without an @ is looked up in the store /remote already maintains, so
# a host has to be named once rather than retyped. Anything containing an @ is
# taken literally — that is what a user@host looks like, and looking it up
# would fail for a machine the user never saved.
if [[ "$HOST" != *"@"* ]]; then
    if [[ -z "$HOSTS_FILE" ]]; then
        HOSTS_FILE="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/remote-hosts.json"
    fi
    if [[ ! -f "$HOSTS_FILE" ]]; then
        echo "Error: no host store at $HOSTS_FILE, so '$HOST' cannot be resolved." >&2
        echo "Save it with: /remote add $HOST <user@host>" >&2
        exit 1
    fi
    resolved=$(jq -r --arg n "$HOST" 'if has($n) then (.[$n].user + "@" + .[$n].host) else empty end' \
        "$HOSTS_FILE" 2>/dev/null | tr -d '\r')
    if [[ -z "$resolved" ]]; then
        echo "Error: host '$HOST' is not in $HOSTS_FILE." >&2
        echo "Save it with: /remote add $HOST <user@host>" >&2
        exit 1
    fi
    # The store keeps a key and ssh_opts because the connection needs them.
    # rsync tunnels over its OWN ssh, so they have to reach it through -e as
    # well — omitting them there fails while a plain ssh to the same host works.
    host_key=$(jq -r --arg n "$HOST" '.[$n].key // empty' "$HOSTS_FILE" 2>/dev/null | tr -d '\r')
    host_opts=$(jq -r --arg n "$HOST" '.[$n].ssh_opts // empty' "$HOSTS_FILE" 2>/dev/null | tr -d '\r')
    [[ -n "$host_key" ]] && SSH_OPTS="$SSH_OPTS -i $host_key"
    [[ -n "$host_opts" ]] && SSH_OPTS="$SSH_OPTS $host_opts"
    HOST="$resolved"
fi

# pwd -P, not $PWD: on macOS /tmp is a symlink to /private/tmp, and a repo
# reached through a symlinked path would rsync from a directory whose name
# does not match what the caller sees.
if [[ -z "$REPO" ]]; then
    REPO="$(pwd -P)"
else
    if [[ ! -d "$REPO" ]]; then
        echo "Error: repo not found: $REPO" >&2
        exit 1
    fi
    REPO="$(cd "$REPO" && pwd -P)"
fi

# Two repos, two runners: claude-council ships tests/run_tests.sh and cs ships
# tests/run_all.sh. Detecting beats making the caller remember which is which,
# and an explicit --cmd still wins.
if [[ -z "$CMD" ]]; then
    for candidate in tests/run_tests.sh tests/run_all.sh; do
        if [[ -f "$REPO/$candidate" ]]; then
            CMD="bash $candidate"
            break
        fi
    done
fi

if [[ -z "$CMD" ]]; then
    echo "Error: no test runner found in $REPO" >&2
    echo "Looked for: tests/run_tests.sh, tests/run_all.sh" >&2
    echo "Pass one explicitly with --cmd 'make test'." >&2
    exit 1
fi

if [[ -z "$REMOTE_DIR" ]]; then
    REMOTE_DIR="ci/$(basename "$REPO")"
fi

# .cs/ holds the session narrative and memory of a cs-managed repo. No suite
# reads it, so it has no reason to exist on a second machine. .git is NOT
# excluded: suites that shell out to git fail confusingly without it.
EXCLUDES=".cs/ .DS_Store node_modules/ target/"

EXCLUDE_ARGS=""
for pat in $EXCLUDES $EXTRA_EXCLUDES; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude $pat"
done

# Built as an array, not a string: a repo path with a space in it would be
# word-split into two arguments by an unquoted expansion, and rsync would then
# copy a directory that does not exist while reporting success.
RSYNC_ARGS=(rsync -az --delete)
if [[ -n "$SSH_OPTS" ]]; then
    RSYNC_ARGS+=(-e "ssh$SSH_OPTS")
fi
for pat in $EXCLUDES $EXTRA_EXCLUDES; do
    RSYNC_ARGS+=(--exclude "$pat")
done
RSYNC_ARGS+=("$REPO/" "$HOST:$REMOTE_DIR/")

RSYNC_CMD="rsync -az --delete${SSH_OPTS:+ -e \"ssh$SSH_OPTS\"}$EXCLUDE_ARGS $REPO/ $HOST:$REMOTE_DIR/"
RUN_CMD="ssh$SSH_OPTS $HOST cd $REMOTE_DIR && $CMD"

if [[ "$PRINT_ONLY" -eq 1 ]]; then
    echo "$RSYNC_CMD"
    echo "$RUN_CMD"
    exit 0
fi

REMOTE_LOG="${REMOTE_DIR}/suite.log"

echo "Syncing $REPO -> $HOST:$REMOTE_DIR"
"${RSYNC_ARGS[@]}"

# Detached, with stdin closed: the run outlives this ssh connection, so a
# dropped link or a finished turn does not kill a suite mid-way.
echo "Starting: $CMD"
# The remote dir and command are expanded HERE on purpose — the remote shell has
# no idea what repo this is. SC2029 is the intended behaviour, not an oversight.
# shellcheck disable=SC2029
# shellcheck disable=SC2086
ssh $SSH_OPTS "$HOST" "mkdir -p $REMOTE_DIR && cd $REMOTE_DIR && rm -f suite.log suite.status && \
    nohup sh -c 'BATS_TEST_TIMEOUT=120 $CMD > suite.log 2>&1; echo \$? > suite.status' \
    < /dev/null > /dev/null 2>&1 & echo \$!"

cat << EOF

Running detached on $HOST.
Follow:  ssh $HOST 'tail -f $REMOTE_LOG'
Result:  ssh $HOST 'tail -20 $REMOTE_LOG; echo "exit=\$(cat ${REMOTE_DIR}/suite.status)"'

The exit code in suite.status is the verdict. Counting TAP "not ok" lines only
works for bats — a runner that prints its own summary yields zero either way.
EOF
