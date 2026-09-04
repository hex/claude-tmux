# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project uses calendar
versioning (`YYYY.M.BUILD`).

## 2026.9.1

### Features
- Run a repo's test suite on a remote host over ssh, detached, so a long suite stops competing with the local machine. `scripts/remote-tests.sh --host mac-mini` from inside the repo.
- Detect the runner (`tests/run_tests.sh`, then `tests/run_all.sh`) unless `--cmd` overrides it; stop and name what it looked for when neither exists.
- Resolve a `--host` without an `@` from the same store `/remote` maintains, and pass its saved `key` and `ssh_opts` to both ssh and rsync. rsync tunnels over its own ssh, so passing them to ssh alone leaves rsync failing against a host that ssh reaches.
- Report the suite's exit code in `suite.status` rather than counting `not ok` lines. A runner that prints its own summary yields zero of those whether it passed or failed.

### Docs
- Document remote test runs in the README, and add the `remote-tests` skill covering when to reach for it and when a local run is still cheaper.

### Other
- Exclude `.cs/` from the sync by default and keep `.git`: suites that shell out to git fail confusingly without it. Test count grew from 41 to 52.

## 2026.7.1

### Features
- Import the `Port` directive from SSH config, so custom-port hosts no longer fall back to 22.
- Split multi-name `Host` lines (e.g. `Host web1 web2`) into separate entries on import, skipping wildcard aliases per-name.
- Route the `remove` subcommand through `/remote`.
- Detect SSH/et connection failures: report the failure and clean up the pane instead of always printing "Connected".
- Open the remote pane in the caller's window under iTerm2's tmux control mode instead of the session's active window.

### Fixes
- Security: escape the SSH key path and remote command with `printf '%q'`. A crafted value in `remote-hosts.json` (including one with an embedded quote) could previously execute arbitrary commands when the connection was typed into the pane.
- Guard the `/remote` command's direct `jq` read against a missing hosts file, and declare `jq` in `allowed-tools`.

### Docs
- Document `remove`, the `import-ssh` improvements, and an updated structure tree in the README.

### Other
- Add shebangs and a GitHub Actions CI workflow (shellcheck + bats); test count grew from 29 to 41 with a new `connect.sh` integration suite.
- Gitignore skill-benchmark artifacts instead of shipping them.
- Simplify `import-ssh` entry construction.
