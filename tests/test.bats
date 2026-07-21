#!/usr/bin/env bats

# Smoke test for the ddev-worktree add-on.
# Run with: bats tests/test.bats   (requires ddev + bats-core installed)

setup() {
  set -eu -o pipefail
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-ddev-worktree"
  export TESTDIR="$(mktemp -d)"
  export DDEV_NONINTERACTIVE=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  ddev config --project-name="${PROJNAME}" --project-type=php >/dev/null
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  [ -n "${TESTDIR:-}" ] && rm -rf "${TESTDIR}"
}

@test "install registers the worktree commands" {
  set -eu -o pipefail
  cd "${TESTDIR}"

  ddev add-on get "${DIR}"
  ddev start -y

  # both commands are discovered
  run ddev worktree-provision -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ddev worktree-provision"* ]]
  [[ "$output" == *"--phpstorm"* ]]

  # editor flags are mutually exclusive
  run ddev worktree-provision my-branch --phpstorm --vscode
  [ "$status" -ne 0 ]
  [[ "$output" == *"pick one editor flag"* ]]

  # missing required arg -> usage + non-zero exit
  run ddev worktree-remove
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: ddev worktree-remove"* ]]

  # running from the main checkout without a branch arg is rejected cleanly
  run ddev worktree-provision
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: ddev worktree-provision"* ]]
}

@test "remove deletes the add-on files" {
  set -eu -o pipefail
  cd "${TESTDIR}"

  ddev add-on get "${DIR}"
  ddev add-on remove worktree

  run ddev worktree-provision -h
  [ "$status" -ne 0 ]
}
