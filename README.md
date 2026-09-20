# absolute-server-template

The template every Absolute game server image starts from. Press **Use this
template**, fill in `manifest.env`, write the game's quirks, and you have a
server image that already meets the
[Absolute engineering standard](https://github.com/abspwgm/.github).

It exists because the alternative is fifty diverging copies of the same update
logic — and the update logic is the part that most needs to be right.

## What you get

| | |
|---|---|
| [`manifest.env`](manifest.env) | Everything that differs between one game and another. Validated at start; a placeholder app id or a wrong stop signal stops the container rather than being guessed. |
| [`scripts/common`](scripts/common) | The shared library: logging, paths, process matching, the credential guard, pinned downloads, SteamCMD build ids. Game-agnostic by construction. |
| [`scripts/manifest`](scripts/manifest) | Loads and validates the manifest. Fails closed. |
| [`tests/unit/`](tests/unit) | The fast tier. No Docker, no network, under a second, and it fails when any of the above stops being true. |
| [`.absolute/policy.yml`](.absolute/policy.yml) | This repository's answers to the standard, which your game repo inherits and edits. |

## Starting a new game

1. **Use this template** on GitHub, named `absolute-<game>-server`.
2. Fill in `manifest.env`. Every field is documented in place; the ones that
   bite are `STOP_SIGNAL` (the wrong one corrupts saves), `READY_LOG_PATTERN`
   (the difference between a health check that works and one that lies) and the
   public/private port split.
3. Run `bash tests/run_unit.sh`. It fails until the manifest is real.
4. Add the game's quirks in `scripts/quirks`, not in `scripts/common`. If you
   find yourself writing `if [[ "${GAME_ID}" == ... ]]` in the shared library,
   the value belongs in the manifest.
5. Work through [`CHECKLIST.md`](CHECKLIST.md). A game ships when every item is
   done, not when it boots once.

## What the manifest replaces

The three original images — Valheim, Rust, Palworld — were the same program with
the constants swapped: the app id, the binary name, the process name, the stop
signal, the ready line, the ports, the save paths. Those are now data:

```sh
GAME_ID=satisfactory            STEAM_APP_ID=1690800
STEAM_PLATFORM=linux            STEAM_BRANCH=public
SERVER_PROCESS=FactoryServer    READY_LOG_PATTERN='Server startup complete'
PUBLIC_PORTS=7777/udp           STOP_SIGNAL=INT
SAVE_PATHS=saved                SNAPSHOT_PATHS=/opt/satisfactory/server
```

## Status

The shared library, the manifest and the fast tier are here and tested. The
container layer — `Dockerfile`, the compose files, the end-to-end suite, the
publish and build-watch workflows — lands with the first real game generated
from this template, because the standard does not let a thing be called proven
until a suite has passed on it. See the exceptions in
[`.absolute/policy.yml`](.absolute/policy.yml), which say exactly that, with
dates.

## Licence

Apache-2.0. See [`LICENSE`](LICENSE).
