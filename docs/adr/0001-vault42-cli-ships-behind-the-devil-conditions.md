# 0001. The vault42 CLI ships only with C1-C18 met

- Status: accepted with conditions (devil ruling 2026-10-18, C1-C18)
- Date: 2026-10-18
- Deciders: devil (ruling); the operator, who runs every credentialed call and the first live push

## Context

- `42ctl env push` (0.1.16) has no `--only`, `--prune` or per-file option: a push always sends the whole scan
  (`42ctl env push --help`). The only native single-value write is `env secret set PATH` (stdin), a key store
  outside the file tree.
- The toolkit diff compares sizes only (`wt-v42/scripts/vault42/inventory.sh:218-238`): a same-length edit
  (a regenerated hex or base64 secret) reads as "in sync".
- groot's team push today adds `--private` for `vendor/*` and `secrets/*.env secrets/*cert* secrets/*key*
  secrets/.* *.local` (`apps/grobase/scripts/vault/ctl-env.sh:67,93`) plus `*.bak` and `.env.grobase-remote`
  (`scripts/vault42-team.sh:71,75`). The design's example config lists only the last two.
- `secrets/*.env` covers the vault42 admin credentials and `secrets/*cert*` the local CA private key
  (comment in `ctl-env.sh:68-80`).
- CI places keystore, contract and session files and exports only `FT_PASSPHRASE`/`VAULT42_PASSPHRASE`
  (`groot .github/workflows/fresh-machine.yml:101-105,168-198`). It has no password, email or tenant.
- `secrets-ensure` falls back to LOCAL mode on any non-team pull failure (`groot utils/mk/repo.mk:198-215`).
  Recovering from LOCAL mode wipes the volumes.
- `make all` fast-forwards every submodule to its branch tip (`repo.mk:65-109`, `pipeline.mk:10-17`). The
  scanner walks `vendor/scripts` as its own tree, so `vendor/scripts/backups/.env.example` is already in groot's push.
- Univers42/scripts has no CI (`ls .github` fails).
- Unknown when this was written: A1 (a push replaces the newest tree) and A2 (whether a push keeps another
  member's private files) have not been checked live. Neither has the `env keys ls` row shape, or whether
  `env pull` preview reports content equality.

## Decision

The CLI is ported from the toolkit, with credentials read from the environment only. It lands on main only
when the criteria in the ruling hold. In short:

- The private set matches the old path byte for byte, and the tool forces privacy for the stage archive and `*.local`.
- The environment cannot override safety keys. Override lookup reads only known (target, key) pairs.
- Hooks are split into argv and never handed to a shell. A hook script must be git-tracked and outside the
  scan, and `post_pull` gets `FT_PASSPHRASE` only.
- File-mode push compares bytes and mode, re-diffs after the confirm, and prints `--only` fixes.
- A missing credential exits 5, which `secrets-ensure` treats as fatal.
- The tool owns the version list. Push accepts no `--any-version`.
- The docker runner mounts at the same path. It uses rootless detection, and `--network host` when needed.
- V8, V9, V15 and V18 keep their defaults, and their markers sit under the git common dir.
- The first live push goes to a throwaway env and is followed by a restore drill.

## Alternatives considered

- **Native single-file push**: does not exist in 0.1.16 (`env push --help`).
- **File mode on the size diff**: misses same-length secret rotations (`inventory.sh:227`).
- **Keep credential-file loading**: the user asked for environment variables only. CI never used the files.
- **Every key env-overridable**: one stray variable disables the push guard or the privacy plan.

## Consequences

- The operator runs `vault42 doctor`, the preview pull and the first push. The agent shell cannot.
- A2 stays printed in every push confirm until a two-account test answers it.
- The VM uses its own identity, granted only the grobase envs (a user decision, still pending).
