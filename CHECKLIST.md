# Release checklist for a new game

A game ships when every line here is done. Booting once is not shipping.

## Manifest

- [ ] `STEAM_APP_ID` is the **dedicated server's** app id, not the client's.
- [ ] `STEAM_BRANCH` is confirmed against Steam, not assumed to be `public`.
      Several titles ship their Linux server on a separate branch.
- [ ] `STOP_SIGNAL` is verified by watching a save complete. The wrong signal
      corrupts worlds, and it corrupts them quietly.
- [ ] `READY_LOG_PATTERN` matches a line that only appears when players can
      actually join, and is anchored enough not to match a startup banner.
- [ ] `PUBLIC_PORTS` and `PRIVATE_PORTS` agree with the compose file and with
      the install guide's port table. Admin ports are private.
- [ ] `SNAPSHOT_PATHS` is enough to return to a working system, not just enough
      to keep the data.

## Tests

- [ ] `bash tests/run_unit.sh` passes.
- [ ] The five shared end-to-end tests pass: start, query, graceful shutdown,
      restart with update, backup with retention.
- [ ] A disaster drill destroys a working install and restores it.
- [ ] The suite has been run cold, with no cached server files.

## Security

- [ ] `.absolute/policy.yml` answers every baseline requirement, and every
      exception has a reason and a date.
- [ ] The conformance check passes.
- [ ] If the game has a remote console, the credential guard covers it and an
      e2e test proves the console is not reachable with a default password.
- [ ] The base image is an approved entry in the library, pinned by digest.
- [ ] Nothing proprietary is inside the published image.

## Documentation

- [ ] `docs/INSTALL.md` is written for someone who has never used Docker, a
      terminal or a router's settings page.
- [ ] Its port table names which ports to forward and which to keep private,
      and links to the shared port forwarding guide.
- [ ] Troubleshooting is keyed by the exact error text a user will see.
- [ ] **Someone who has not seen the guide completed it on a clean machine
      without asking a question.** This is the one that is always skipped, and
      it is the one that decides whether the image is usable.

## Registry

- [ ] The game's entry in `games.json` matches the manifest: ports, app id,
      runtime, mod source.
- [ ] Every `unverified` note in that entry is now confirmed or removed.
