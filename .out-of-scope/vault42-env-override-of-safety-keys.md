# Env override of vault42 safety keys is out of scope

- Decided: 2026-10-18 · by devil (ADR 0001)
- Holds while: a single push can publish to every key holder, and nothing on the server can undo that

## The concept

Every `vault42.conf` key can be overridden from the environment as `VAULT42_<TARGET>_<KEY>`. That covers
`pre_push`, `post_pull`, `private`, `guard`, `refuse_on_env`, `mode`, `stage_unscanned_as` and the versions
list, so a machine or CI job can retune the tool without editing the committed file.

## Why not

- `pre_push` is the push guard that stops a tree from losing prod dumps (`groot scripts/vault42-push-guard.sh`).
  Setting `VAULT42_SECRETS_PRE_PUSH=true` would skip it.
- An empty `private` sends `secrets/*.env` (vault42 admin credentials) and the CA private key shared to every
  key holder (`grobase scripts/vault/ctl-env.sh:68-93`). Disclosure cannot be undone, only rotated.
- CI exports `VAULT42_SESSION_B64`, `VAULT42_KEYSTORE_B64`, `VAULT42_CONTRACT_B64` and `VAULT42_SOURCE`
  (`groot .github/workflows/fresh-machine.yml:101-105,203`). A prefix scan would read them as overrides.
- The answer would change if 42ctl gained a server-side undo for one push (an `env pull --at REV` plus a
  revert), and if a disclosed path could be withdrawn before anyone read it.

`root`, `stage_dir`, `min_free_mb` (raise only) and adding to `private` stay overridable.

## Prior requests

- 2026-10-18 (vault42 CLI design): every key overridable by env.

## Reopen when

`42ctl env push --help` or `env pull --help` documents a revision rollback for shared environments.
