#!/usr/bin/env bats

# Smoke test for the ddev-worktree add-on.
# Run with: bats tests/test.bats   (requires ddev + bats-core installed)

setup() {
  set -eu -o pipefail
  export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-ddev-worktree"
  # Resolved: on macOS mktemp -d hands back /var/... for /private/var/..., and
  # DDEV registers a project under the exact path it was configured from, so an
  # unresolved test dir makes project lookup from a subdirectory miss.
  export TESTDIR="$(cd "$(mktemp -d)" && pwd -P)"
  export DDEV_NONINTERACTIVE=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  ddev config --project-name="${PROJNAME}" --project-type=php >/dev/null
}

teardown() {
  set -eu -o pipefail
  # Worktrees provisioned by a test get their own DDEV project, named
  # <source>-<branch>; drop those before the source so nothing is left running.
  ddev delete -Oy "${PROJNAME}-nodb" >/dev/null 2>&1 || true
  ddev delete -Oy "${PROJNAME}-seed" >/dev/null 2>&1 || true
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

@test "remove refuses uncommitted tracked edits before touching the DDEV project" {
  set -eu -o pipefail
  cd "${TESTDIR}"

  ddev add-on get "${DIR}"

  git init -q .
  echo original > tracked.txt
  git add tracked.txt
  git -c user.email=t@example.com -c user.name=Test commit -q -m init
  git worktree add .worktrees/dirty -b dirty >/dev/null
  echo edited > .worktrees/dirty/tracked.txt

  run ddev worktree-remove dirty
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes to tracked files"* ]]
  # `ddev delete` drops the database for good, so nothing may be torn down first
  [[ "$output" != *"DDEV project"* ]]
}

@test "provisions a project that has no db container and no .env" {
  set -eu -o pipefail
  cd "${TESTDIR}"

  ddev add-on get "${DIR}"

  # A library-style project: no database, no .env — nothing to seed.
  ddev config --omit-containers=db >/dev/null

  git init -q .
  echo lib > README.md
  git add README.md .ddev
  git -c user.email=t@example.com -c user.name=Test commit -q -m init

  ddev start -y >/dev/null

  run ddev worktree-provision nodb
  [ "$status" -eq 0 ]
  [[ "$output" == *"no db container; skipping database copy"* ]]
  [[ "$output" == *"no .env"* ]]
  [[ "$output" == *"nothing to seed"* ]]

  # The worktree exists and its own DDEV project is up.
  [ -e .worktrees/nodb/.git ]
  run ddev describe -j "${PROJNAME}-nodb"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"running"'* ]]

  # DDEV must resolve to the worktree from inside it. .worktrees/<branch> is
  # nested in the source approot, and since DDEV v1.25.4 an unregistered nested
  # project is passed over for the one around it — which would point every
  # command here at the source checkout instead.
  cd .worktrees/nodb
  run ddev describe -j
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"name\":\"${PROJNAME}-nodb\""* ]]
  # Compare resolved paths: a temp dir reaches here through a symlink.
  approot=$(printf '%s' "$output" | grep -o '"approot":"[^"]*"' | head -n1 | cut -d'"' -f4)
  [ "$(cd "$approot" && pwd -P)" = "$(pwd -P)" ]
}

@test "seeding .ddev keeps the checkout's own files" {
  set -eu -o pipefail
  cd "${TESTDIR}"

  ddev add-on get "${DIR}"
  ddev config --omit-containers=db >/dev/null

  # A repo that tracks part of .ddev/ and ignores the rest — committing command
  # files while config.yaml stays ignored is what the README recommends for
  # worktrunk. The tracked ones belong to the branch, not to the source.
  git init -q .
  printf '/.ddev/config.yaml\n.worktrees/\n' > .gitignore
  mkdir -p .ddev/commands/host
  echo branch-version > .ddev/commands/host/marker
  chmod +x .ddev/commands/host/marker   # DDEV makes command files executable
  git add .gitignore .ddev/commands/host/marker
  git -c user.email=t@example.com -c user.name=Test commit -q -m init

  # The source's copy now differs from the committed one, so a clobber shows up.
  echo source-version > .ddev/commands/host/marker

  ddev start -y >/dev/null

  run ddev worktree-provision seed
  [ "$status" -eq 0 ]
  [[ "$output" == *"seeding it from the source"* ]]

  # config.yaml was missing, so it gets seeded...
  [ -f .worktrees/seed/.ddev/config.yaml ]
  # ...but the branch's own command file is left alone.
  [ "$(cat .worktrees/seed/.ddev/commands/host/marker)" = "branch-version" ]

  # And no tracked file in the worktree was touched.
  run git -C .worktrees/seed status --porcelain --untracked-files=no
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remove resolves the worktree in a custom WORKTREES_DIR" {
  set -eu -o pipefail
  cd "${TESTDIR}"

  ddev add-on get "${DIR}"
  echo 'WORKTREES_DIR=custom-wt' >> .ddev/worktree.conf

  git init -q .
  git -c user.email=t@example.com -c user.name=Test commit -q --allow-empty -m init
  git worktree add custom-wt/spike -b spike >/dev/null

  run ddev worktree-remove spike
  [ "$status" -eq 0 ]
  [ ! -d custom-wt/spike ]
}

@test "provision reads WORKTREES_DIR from the main checkout, not the invoking worktree" {
  set -eu -o pipefail

  # Stubbed ddev: enough for worktree-provision to resolve the target and add the
  # worktree, which is all this test looks at. It then fails on a later call.
  STUB="${TESTDIR}/stub"
  mkdir -p "$STUB"
  cat > "$STUB/ddev" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  describe) printf '{"status":"running"}\n' ;;
  exec) case "$*" in *SITENAME*) printf 'base' ;; *TLD*) printf 'ddev.site' ;; esac ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/ddev"

  REPO="${TESTDIR}/repo"
  mkdir -p "$REPO/.ddev"
  cd "$REPO"
  git init -q .
  printf '.env\n' > .gitignore
  printf 'name: base\n' > .ddev/config.yaml
  printf 'WORKTREES_DIR=main-dir\n' > .ddev/worktree.conf
  git add -A
  git -c user.email=t@example.com -c user.name=Test commit -q -m init
  printf 'APP_URL=https://old\n' > .env

  # a linked worktree whose own copy of the config disagrees
  git worktree add linked -b linked >/dev/null
  printf 'WORKTREES_DIR=linked-dir\n' > linked/.ddev/worktree.conf
  printf 'APP_URL=https://old\n' > linked/.env

  cd "$REPO/linked"
  run env PATH="$STUB:$PATH" DDEV_APPROOT="$REPO/linked" \
    bash "${DIR}/commands/host/worktree-provision" spike

  # worktree-remove resolves the main checkout's value, so provision must too
  [ -d "$REPO/main-dir/spike" ]
  [ ! -d "$REPO/linked/linked-dir/spike" ]
  [ ! -d "$REPO/linked-dir/spike" ]
}

@test "remove deletes the add-on files" {
  set -eu -o pipefail
  cd "${TESTDIR}"

  ddev add-on get "${DIR}"
  ddev add-on remove worktree

  run ddev worktree-provision -h
  [ "$status" -ne 0 ]
}
