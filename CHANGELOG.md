# Changelog

## 0.4.0

The release that makes Cleared something you can leave running.

### Fixed

- **Cleared did nothing until its icon was first clicked.** Polling started
  from the panel, which macOS does not build until it is opened, so an app
  launched at login watched nothing and announced nothing. It now starts with
  the app.
- **A fresh clone did not build.** `project.yml` pointed at `Local.xcconfig`,
  which is gitignored. The include is now optional.
- **Merge was offered on pull requests GitHub would refuse.** Readiness looked
  only at checks and conflicts. It now also requires GitHub's own merge verdict,
  so a pull request waiting on a required review, behind its base branch, or
  blocked by a branch rule is listed under *In flight* with the reason.
- **A merge could include commits nobody had seen.** The merge is now pinned to
  the commit Cleared last polled; a push in between is refused by GitHub.
- **The merge method setting failed outright on repositories that don't allow
  it.** Those repositories now use their own default.
- **Start a workflow listed workflows that can't be started**, always sent no
  inputs, and assumed the branch was `main`. It now lists only workflows with a
  `workflow_dispatch` trigger, shows their declared inputs, and defaults to the
  repository's default branch.
- **The "calls left" figure jumped around.** It mixed the REST and GraphQL
  budgets; it now shows the REST budget, which is the one polling spends.
- **A revoked token caused an error banner on every poll.** Cleared now stops
  and returns to the connect screen with an explanation.
- **Ignoring a repository could not be undone**, and pinned repositories had no
  interface at all.
- "Notify on failed runs" had no effect. A newer banner could be dismissed by
  the previous banner's timer. `⌘1`–`⌘9` were attached to rows rather than to
  the Merge buttons, and every row past the ninth shared `⌘↩`.

### Added

- Launch at login, an app icon, and `make install`.
- *Clear* and *Re-run failed jobs* buttons on notifications. A hold's
  notification is withdrawn once the hold is gone.
- Reject a held deployment, from a row's right-click menu.
- An optional two-click confirmation for Clear and Merge.
- Rate-limit handling: when GitHub says to stop, Cleared waits until the time
  it was given.
- Repositories are rediscovered hourly, so new ones appear without a restart.
- Timestamps in the panel tick while it is open.
- Logging to the unified log under `net.hlnd.Cleared`.
- CI on pull requests, and a script that produces a notarized build.

### Changed

- The token only needs the `repo` scope. Earlier versions asked for `workflow`
  as well, which nothing Cleared does requires.
- Failed runs older than 30 days are no longer listed, since GitHub won't
  re-run them.
- Release builds use the hardened runtime.

## 0.3.0

Initial public version, plus a fix so the panel sizes to its queue.
