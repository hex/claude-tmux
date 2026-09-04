---
name: Remote test runs
description: This skill should be used when a full test suite is about to run and would take minutes rather than seconds, when the user asks to "run the tests on another machine", "run the suite remotely", "run tests on the mac studio", or when a local suite has already slowed or frozen the machine. Runs a repo's suite on a saved remote host over ssh, detached, and reports the exit code. Not for a single test file or a --changed run, where the sync costs more than it saves.
version: 2026.9.1
---
<!-- ABOUTME: Runs a repository's test suite on a remote host instead of locally. -->

# Running a test suite on another machine

A suite that takes ten minutes locally competes with everything else on the
machine. `remote-tests.sh` copies the repo to a saved host, starts the suite
there detached, and returns a command that reports the real exit code.

This is the batch counterpart to the `remote` skill: that one drives an
interactive pane with send-keys, this one fires a long job and walks away.

## Use it when

- A full suite is about to run and takes minutes. A suite heavy enough to slow
  the machine is the clearest case.
- The user asks for tests to run remotely or on a named machine.
- A local run is already making the machine unusable.

Do **not** use it for one test file or a `--changed` run. Syncing costs more
than those save, and that feedback loop belongs local.

## Invoking

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/remote-tests.sh --host mac-mini
```

Run from inside the repo. It resolves `pwd -P`, detects the runner, syncs, and
starts. `--print` shows the commands without running anything.

| Flag | Meaning |
|------|---------|
| `--host NAME` | A host saved by `/remote`, or a literal `user@host` |
| `--hosts-file PATH` | Host store (default: the plugin's `remote-hosts.json`) |
| `--repo DIR` | Repo to copy (default: current directory) |
| `--cmd CMD` | Test command; overrides detection |
| `--remote-dir DIR` | Where to put it (default `ci/<basename>`) |
| `--exclude PATTERN` | Extra rsync exclude, repeatable |
| `--print` | Print the commands and exit |

A `--host` with no `@` is looked up in the store `/remote` maintains, and its
saved `key` and `ssh_opts` are passed to **both** ssh and rsync — rsync tunnels
over its own ssh, so omitting them there fails while a plain ssh succeeds.
An unknown name stops and points at `/remote add` rather than guessing.

Runner detection looks for `tests/run_tests.sh` then `tests/run_all.sh`, and
stops with the list of what it looked for if neither exists.

## What is excluded, and why it matters

`.cs/` is excluded by default: in a cs-managed repo it holds the session
narrative and memory files, no suite reads them, and they should not be copied
to a second machine.

`.git` is **not** excluded. Suites that shell out to git fail in a way that
reads like a real defect when it is missing.

## Reading the result

The run is detached under `nohup` with stdin closed, so it survives the ssh
connection ending. The verdict is the exit code in `suite.status`, not a count
of TAP `not ok` lines — a runner that prints its own summary yields zero of
those whether it passed or failed.

Wait on the remote pid from a background shell rather than polling in the
foreground:

```bash
while ssh <host> 'kill -0 <pid> 2>/dev/null'; do sleep 30; done
```

## First run on a new host

Check the dependencies before blaming the suite: `bats` and `jq` are the usual
gaps (`brew install bats-core jq`). Confirm git identity is set there too — a
host with none makes any test that commits fail for an unrelated-looking reason.
