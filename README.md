# ddev-worktree

> ⚠️ **Experimental.** This add-on is new and under active development. It has
> been verified on SWIS Laravel and Drupal projects, but expect rough edges and
> breaking changes before a 1.0 release. Use on throwaway worktrees, not on
> anything you can't afford to lose.

A [DDEV](https://ddev.com) add-on that turns a git worktree into a fully isolated
DDEV project in one command — its own project name, hostname, database, and
dependencies — so you can run several branches side by side without them
fighting over the same containers, ports, or database.

Works with any DDEV project type. Built for and tested against SWIS Laravel and
Drupal projects.

## Install

```bash
ddev add-on get swisnl/ddev-worktree
```

Re-run the same command to update; `ddev add-on remove worktree` to uninstall
(this only removes the commands — it never touches worktrees you created).

## Usage

Run from the **main checkout** (or any worktree):

```bash
# create branch `my-feature` off HEAD, provision it, seed from this project
ddev worktree-provision my-feature

# branch off a specific ref instead of HEAD
ddev worktree-provision hotfix --from develop
ddev worktree-provision fix-123 --from v2.1.0

# branch off AND seed data from another checkout on disk
ddev worktree-provision spike --from ../other-checkout

# tear it all down (DDEV project + git worktree)
ddev worktree-remove my-feature
ddev worktree-remove my-feature --force   # also discard uncommitted edits to tracked files
```

`worktree-provision <branch> [--from <ref|path>]`:

1. creates `.worktrees/<branch>` under the main checkout (new or existing branch),
2. gives it its own DDEV project `‹source-name›-‹branch›` at its own hostname,
3. copies `.env` from the source and repoints the host/URL vars (see Config),
4. installs dependencies (`composer install`, plus `npm ci` / `yarn` / `pnpm` /
   `bun` by detected lockfile) — reading `composer.json`/`package.json` so
   framework install paths like Drupal's `installer-paths` are honoured,
5. exports the source database and imports it,
6. starts the project, running its normal post-start hooks once everything is in
   place.

The **source** (the project supplying `.env` + database) must be running; it
defaults to the project you run the command in, or the `--from` path if that is
a checkout on disk.

## Config

The command repoints a fixed set of `.env` keys at the new worktree's hostname.
Defaults suit SWIS projects:

| Set to `<host>`            | Set to `https://<host>` |
| -------------------------- | ----------------------- |
| `APP_DOMAIN`               | `APP_URL`               |
| `SESSION_DOMAIN`           |                         |
| `SANCTUM_STATEFUL_DOMAINS` |                         |

Keys not present in a given `.env` are skipped. To change the list for a repo,
create `.ddev/worktree.conf` (not managed by this add-on, so updates leave it
alone):

```bash
# .ddev/worktree.conf
ENV_HOST_VARS=(APP_DOMAIN COOKIE_DOMAIN)
ENV_URL_VARS=(APP_URL VITE_APP_URL)
```

## Using with worktrunk (or another worktree manager)

If you drive worktrees with [worktrunk](https://worktrunk.dev) (`wt`), let it own
worktree creation/removal and use this add-on only to provision the DDEV
environment, via the `--in-place` flag:

- `ddev worktree-provision --in-place [--from <path>]` — provision the worktree
  you're **already in** instead of creating one. Seeds from `--from`, else from
  the primary worktree.
- `ddev worktree-remove --in-place` — tear down just the DDEV project for the
  current worktree, leaving the git worktree for `wt` to remove.

Set it up once:

```bash
# 1. install worktrunk (see https://worktrunk.dev for other platforms)
brew install worktrunk

# 2. install this add-on in the repo and commit its command files so worktrunk's
#    worktrees (which only carry tracked files) can find them
ddev add-on get swisnl/ddev-worktree
git add .ddev/commands/host/worktree-* && git commit -m "add ddev-worktree commands"

# 3. optional: shell integration so `wt switch` also cd's you into the worktree
wt config shell install
```

Then wire the hooks into `.config/wt.toml` in the repo root:

```toml
[post-start]
ddev = "ddev worktree-provision --in-place --from {{ primary_worktree_path }}"

[pre-remove]
ddev = "ddev worktree-remove --in-place"
```

Notes for this setup:

- **Commit the add-on's command files** (`.ddev/commands/host/worktree-*`). A new
  git worktree only contains *tracked* files, so if they're untracked `wt`'s
  worktree won't have them and the hook can't find `ddev worktree-provision`.
  (Alternatively, point the hook at the script by absolute path.)
- **The primary worktree's DDEV project must be running** when `post-start`
  fires — that's where the database and `.env` are copied from.
- worktrunk asks you to approve hook commands the first time
  (`wt config approvals add`, or `wt switch --yes`).

## Notes

- Add `.worktrees/` and `.ddev/config.local.yaml` to the project's `.gitignore`.
  A committed `.ddev/config.yaml` should **not** pin `name:` — the add-on writes
  the per-worktree name into `.ddev/config.local.yaml`.
- Package managers other than npm must be available in the web container
  (usually via `corepack_enable: true` in `.ddev/config.yaml`, which every
  worktree inherits). If a tool is missing the JS step warns and continues.

## Requirements

DDEV `>= 1.24.0`, macOS or Linux.
