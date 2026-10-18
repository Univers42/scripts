# vault42

Move a project's environment files, secrets and docker volumes through a 42ctl vault, from one
config file, with every credential read from the environment. Bash 4.4+, no dependency beyond
`git`, `flock`, `awk`, `tar`/`gzip` and 42ctl (native, or a pinned docker image).

Tested against 42ctl 0.1.15 and 0.1.16 through a fake; see [What was not verified](#what-was-not-verified).

## Use

```text
vault42 [--config PATH] [--target NAME] [--kind env|secrets|volumes|all]... COMMAND [ARGS]
```

`--config` falls back to `$VAULT42_CONFIG`, then `./vault42.conf`. `--kind` is repeatable and
defaults to `env secrets`: volumes are never implied. Start from [`vault42.conf.example`](vault42.conf.example).

| command | what it does |
|---|---|
| `doctor` (`status`) | read-only checks of 42ctl, the environment, the session and your key |
| `login` | log in with `FT_EMAIL`, `FT_PASSWORD`, `FT_TENANT` |
| `keys ls` | who holds a key to each target's env |
| `list`, `diff`, `find PATTERN` | read-only views of the vault |
| `pull [--apply] [--only PATH]...` | preview, or restore, the vault's files; `post_pull` runs after `--apply` |
| `push [--yes] [--personal] [--share PATH] [--private PAT] [FILE...]` | replace the vault's tree with this checkout, or push named files |
| `secret get\|set PATH` | one vault secret; `set` reads stdin |
| `config show` | the effective configuration |
| `volumes list\|capture [--plan] [--only NAME]\|restore [--force] ARCHIVE\|NAME\|restore --all` | docker volume archives |
| `help [command]` | usage |

Exit codes: 0 ok, 1 failed or refused, 2 usage or invalid config, 3 pushed to a personal vault,
4 locked by another vault42, 5 missing credential.

Output below is copied from a run against the fake 42ctl (`tests/helpers/fake-42ctl`).

```text
$ vault42 doctor
OK   42ctl          0.1.16 via native
OK   config         target app: o/p/e, kinds env secrets
OK   FT_PASSPHRASE  set
SKIP FT_PASSWORD    unset; needed only by `vault42 login`
SKIP FT_EMAIL       unset; needed only by `vault42 login`
SKIP FT_TENANT      unset; needed only by `vault42 login`
OK   keystore       unlocked
OK   session        the server accepts the session
OK   keys app       your key is active

$ vault42 push --yes
[vault42] push app -> o/p/e
+ a.env
+ secrets/k.env
[vault42] 2 added, 0 dropped, 0 changed
[vault42] files another member pushed private are invisible to you; whether the server keeps them across your push is UNVERIFIED
[vault42] active key holders who will read this tree: 7704efb0-5a6a-4117-9cdd-a9265a8fc350
[vault42] the vault matches this checkout and its private set is the planned one

$ vault42 list
[app]
         4 shared  a.env
         4 private secrets/k.env

$ vault42 diff
[app] 0 added, 0 dropped, 1 changed
~ a.env 5->4 bytes
restore with:
  vault42 pull --apply --only a.env

$ vault42 pull
would write a.env
would write secrets/k.env
2 file(s)
[vault42] preview only: add --apply to write these files

$ vault42 list        # FT_PASSPHRASE unset
vault42: FT_PASSPHRASE is not set; export it (credentials are read from the environment only, never from a file)
```

## Credentials

Environment only. No credential file is read, no value reaches stdout, stderr, argv, a log or a file.

| name | needed by | alias, used only when the canonical name is unset (doctor says which) |
|---|---|---|
| `FT_PASSPHRASE` | everything but `login`, `help`, `config show` | `VAULT42_PASSPHRASE` |
| `FT_PASSWORD`, `FT_EMAIL`, `FT_TENANT` | `login` only | `FT_LOGIN_EMAIL` for the email |
| `VAULT42_REGISTER_TOKEN` | registration | `FT_REGISTER_TOKEN` |
| `FT_S3_KEY`, `FT_S3_SECRET` | private files over 4128768 bytes | none |

42ctl's own spellings are derived in the child's environment only. `FT_TENANT` has no 42ctl
environment variable, so `login` passes it as `--tenant NAME` in argv: a tenant name is visible in
the process list; it is not a secret.

## doctor exit code

5 when `FT_PASSPHRASE` is missing, else 2 when the config is invalid, else 1 when any check is
`FAIL`, else 0. `FT_PASSWORD`, `FT_EMAIL` and `FT_TENANT` are `SKIP` when unset, so a CI run with only the
passphrase exits 0. A reachable authority with a failing `42ctl auth me` is a `FAIL`. An unlisted
42ctl version is a `WARN` for doctor, pull and list, and a refusal (exit 1) for push.

## What it does NOT do

- It does not create or initialise an env, sync, grant or rotate keys. `env init` and `keys sync` are never called.
- It does not read a credential from a file, a prompt or a flag. Config keys can be overridden from the environment
  only for `VAULT42_<TARGET>_{ROOT,STAGE_DIR,MIN_FREE_MB,PRIVATE_ADD}`; the floor can only be raised and patterns only
  added, so no variable weakens a guard (ADR 0001).
- It does not push volumes unless `--kind volumes` is given, and does not mix volumes with other kinds in a target.
- `push --kind env` on a target holding `env secrets` exits 2: `env push` replaces the whole tree.
- It does not run a hook that is under `secrets/`, in the scan, or untracked (exit 2). Hooks are exec'd as argv, never through a shell.
- It does not capture volumes of a staging or prod stack, whatever the flags.
- It does not fall back to the personal vault on a failed key check. That needs `personal_fallback = yes`
  in the config and `--personal` on the line; `--yes` alone never does it. It then exits 3.
- It does not prove a teammate's key opens a tree, or that the server keeps another member's private files across your push.

## Safety behaviours worth knowing

- A mutating command takes a lock; a second one exits 4. `post_pull` runs after the lock is released,
  so a hook may call `vault42 secret get` without deadlocking.
- Push compares sizes for the table and re-diffs after the confirm. File-mode push compares bytes and mode.
- Every restore hint is `vault42 pull --apply --only PATH`, never a bare `pull --apply`.
- State (locks, the stopped-container record, the restore-drill marker) lives under the git common dir
  (`<git-common-dir>/vault42/`), so a linked worktree or a submodule shares it and the scan never sees it.
  Temp dirs are mode 700 under `<git-common-dir>/vault42-tmp/` and are removed on exit and signals.
- 42ctl runs with stdin from `/dev/null`. Through docker the credentials are forwarded by name (`-e NAME`);
  a docker push needs an image pinned `name@sha256:<64 hex>`.

## First live push (C18)

Nothing here has run against a live vault. The first live push is yours, on a throwaway env:

1. Create the throwaway env by hand with 42ctl and point a target at it.
2. `vault42 doctor`, then `vault42 push` and read the A2 line it prints before you answer `y`.
3. In an empty directory with the same config: `vault42 pull --apply`, then `diff -r` against the checkout.
4. Only if the diff is empty (modes included), point the config at the real env.

## Assumptions and caveats

- A2: a push replaces the newest tree. Files another member pushed as private are invisible to you,
  and whether the server keeps them across your push is unverified. The confirm prints this every time.
- A3: `login` passes `--password` bare and trusts 42ctl to read `FT_PASSWORD` from its environment.
- `diff` compares sizes: a same-size edit is invisible to it. `push FILE`, the verify after a push and
  the volumes drill compare bytes.
- Private-file ceiling is 4128768 bytes; larger files need the `FT_S3_*` pair.
- The scanner is name-based (`*.env*`, `secrets/` directories); a secret in any other filename is not seen.
- Volumes: sizes come from `docker system df -v` (about 0.5 percent off; compression ignored). A capture is a
  cold copy: containers using the volume are stopped and restarted on every exit path; one started by
  something else in between is not tracked. Never move a volumes root after its first push.
- `guard = sole-holder`: refuses a volumes push unless the env exists under its exact name, nobody
  else is `active`, and your wrap unwraps; after the push it restores into a scratch dir and compares bytes before
  writing the drilled marker. It cannot see an admin who re-keyed and planted a wrap for you.

## Not ported

`run`, `shell` and `stage` (as commands), `backup`, the hard-coded project table, republish's follow-up steps
and the wrapper call into groot. `stage` survives only as the `stage_*` config keys used by `push`.

## What was not verified

No credentialed or state-changing 42ctl call was made while building this: every behaviour is proven
against `tests/helpers/fake-42ctl`, modelled on `42ctl --help` and `--version` of 0.1.16. Its wording
of "holds no tree" and "no row matches" is matched as text.

## Tests and gates

```text
bash -c 'docker run --rm -v "$PWD:$PWD" -w "$PWD" --entrypoint sh bats/bats:1.11.1 -c \
  "apk add -q --no-cache coreutils git jq findutils bash diffutils curl && bats --tap vault42/tests"'
shellcheck -x vault42/vault42.sh vault42/cmd/*.sh vault42/lib/*.sh
shfmt -i 2 -ci -d vault42
```

`shfmt` runs with `-i 2 -ci`, the flags of the toolkit this was ported from; the repo has no `.editorconfig`.
