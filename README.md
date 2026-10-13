<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="GitCleared icon: a white air traffic control tower on an amber tile">
</p>

<h1 align="center">GitCleared</h1>

<p align="center">
  <strong>Tower control for your GitHub deploys.</strong><br>
  Clear held deployments for takeoff and bring green pull requests in to land,<br>
  from the macOS menu bar.
</p>

---

Every other GitHub menu bar app is a radar screen. RepoBar, PullBar, GitBar,
Deplog — excellent, all of them — show you the traffic and then send you to a
browser tab to do anything about it. GitCleared is the tower. It issues the
clearances.

There are four, and it does nothing else:

| The call | The button | What it does | GitHub API |
|---|---|---|---|
| **Cleared for takeoff** | *Clear* | Approves a deployment holding at an environment gate you're a required reviewer on | `POST /actions/runs/{id}/pending_deployments` |
| **Cleared to land** | *Merge* | Merges a green pull request — squash by default — when checks pass and nothing conflicts | `PUT /pulls/{n}/merge` |
| **Go around** | *Re-run* | Re-runs the failed jobs of a run | `POST /actions/runs/{id}/rerun-failed-jobs` |
| **Push back** | *Start a workflow* | Starts a workflow by hand | `POST /actions/workflows/{id}/dispatches` |

The strip board is ordered by what is waiting on you, not by repository. A
production deploy holding short of the runway is the top strip whichever repo
it belongs to, because that is the one burning fuel.

**No clearance GitHub wouldn't honour.** A pull request is only cleared to land
when its checks are green *and* GitHub reports no review or branch rule in the
way, and the merge is pinned to the commit GitCleared last had on radar — so a
push that arrives between sweeps is refused, not merged unseen. *Start a
workflow* lists only workflows that declare `workflow_dispatch`, with the
inputs each one's file declares.

## Why there's a tower

Environment gates with required reviewers don't fail — they hold. A deploy sits
in `waiting` until the one person named as a reviewer happens to look at the
right browser tab. Measured across a month of one heavy user's repositories,
the median gated deploy waited over half an hour to start; the worst sat for
eight days. Nothing was broken. Nobody was in the tower.

GitCleared puts that queue in the menu bar and makes clearing it one click.

## Phraseology

The panel already talks like a tower. If you'd rather it spoke GitHub:

| On the board | In GitHub terms |
|---|---|
| **Holding** | A deployment waiting at an environment gate for your approval |
| **Ready to merge** | A pull request on final: green, approved where required, nothing in the way |
| **In flight** | An open pull request that can't land yet, with the reason — *needs review*, *checks running*, *behind base branch*, *conflicts* |
| **Failed** | A run that went wrong, with a go-around on offer |
| **All clear** | Nothing is waiting on you |

## Preflight — installing

Requires macOS 14+, and Xcode 16+ with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) to build. There is no signed download yet, so for now
GitCleared is built from source:

```sh
git clone https://github.com/hollandcloud/cleared.git
cd cleared
make install      # builds Release, copies it to /Applications, launches it
```

Then turn on *Settings → Launch at login*. The tower is staffed from the moment
it launches — you don't need to open the panel for a hold to be noticed.

`make run` builds and launches without installing, which is fine for a look
but can't be registered to launch at login.

Or open it in Xcode:

```sh
make generate     # writes Cleared.xcodeproj from project.yml
open Cleared.xcodeproj
```

`Cleared.xcodeproj` is generated and deliberately not committed — `project.yml`
is the source of truth. (The app was called Cleared until 0.4.1. The project,
the Swift module and the bundle identifier keep that name on purpose: changing
the identifier would throw away everyone's saved token and settings.)

## Squawk — connecting to GitHub

A tower needs to know who is calling. GitCleared needs a GitHub token with the
**`repo`** scope.

- **If you use the `gh` CLI:** click *Use my gh CLI login*. GitCleared shells
  out to `gh auth token` once and stores the result.
- **Otherwise:** paste a personal access token. *Create a token on GitHub…*
  opens the new-token page with the scope already selected.

The Mac App Store version only offers the second. It runs in the App Sandbox,
which lets it neither run `gh` nor read the login `gh` keeps.

The token is written to your login Keychain under `net.hlnd.Cleared` and read
back per request. It is never written to `UserDefaults`, never written to disk
in the clear, and never logged — the only representation GitCleared will ever
display is a fingerprint like `ghp_…2345 · 40 chars`.

To revoke: *Settings → Disconnect and forget token*, which deletes the Keychain
item. Revoke the token itself on GitHub. If GitHub starts rejecting the token —
revoked, or expired — GitCleared stops its sweeps and returns to the connect
screen saying so, rather than going quiet on frequency.

### Why `repo`

Approving a deployment, merging, re-running jobs and dispatching a workflow all
require `repo` on a classic token; GitHub offers nothing narrower. (`workflow`
is not needed — that scope is for editing workflow files, which GitCleared
never does.)

If that's more authority than you want a menu bar app to hold, use a
fine-grained token limited to the repositories you want it to control, with
these repository permissions:

| Permission | Access | Used for |
|---|---|---|
| Actions | Read and write | Listing runs, re-running jobs, starting workflows |
| Deployments | Read and write | Approving or rejecting a held deployment |
| Contents | Read and write | Merging; reading workflow files for their inputs |
| Pull requests | Read | Listing your open pull requests |

Organizations that enforce SAML single sign-on also need the token authorized
for that organization on GitHub.

## Working the board

- **Click a strip** to open it on GitHub. **Right-click** for *Copy Link* — and,
  on a held deployment, *Reject…*, which sends it back to the gate: the waiting
  jobs are cancelled, with your reason on the run.
- **⌘1–⌘9** land the first nine ready pull requests, in the order shown.
  **⌘R** sweeps again, **⌘,** opens Settings, **⌘Q** closes the tower.
- **The tower calls you.** A notification appears when a deployment starts
  holding, with a *Clear* button on it. It is withdrawn once the hold is gone,
  whoever cleared it.
- **Read-back, if you want it.** *Settings → Ask before clearing or merging*
  turns each button into a two-click *Sure?*. It is off by default: one click
  is the point.

## Flow control — staying inside the rate limit

Sweeping every repository every 30 seconds would burn 5,000 requests an hour on
its own. GitCleared avoids that:

- **Conditional requests.** Every sweep sends `If-None-Match`. GitHub does not
  charge a `304` against the hourly limit, and a repository with nothing
  waiting returns a byte-identical body forever — so quiet airspace is free.
- **One GraphQL query** covers open pull requests and their check rollups
  across every repository, rather than one REST call per repo.
- **Backing off.** Sweeps slow by 4× while the panel is closed, and by a further
  4× when fewer than 500 calls remain.
- **Honouring a ground stop.** If GitHub answers with a rate limit, GitCleared
  sends nothing further on that budget until the time GitHub named, instead of
  retrying into it.

Remaining budget is shown in the footer. When a sweep comes back short — no
network, rate limited — the footer says why and how stale the board is.

## Your airspace — which repositories it watches

GitCleared ships with **no repository list**. On first connect it asks GitHub
for repositories you've pushed to in the last 90 days (configurable) and
watches the 20 most recent, re-checking hourly so a new repository comes onto
the scope without a restart. In Settings you can ignore any of them (and
un-ignore them later), or pin a repository so it stays watched however long it
has been quiet.

This is deliberate: it means the source of this public repository reveals
nothing about which repositories anyone actually tracks, and low-traffic repos
that see one PR a month get picked up without being added by hand.

## Ground crew — development

```sh
make build                      # debug build
make test                       # unit tests
make install                    # Release build into /Applications
make appstore-build             # the sandboxed App Store configuration
make preview                    # render the panel against sample data
make preview FIXTURE=overflow   # ... with enough rows to scroll
make preview FIXTURE=empty      # ... the all-clear state
make preview FIXTURE=connect    # ... the connect screen (connect-appstore for the store build's)
make icon                       # redraw the app icon from Scripts/make-icon.swift
make scan                       # refuse to commit anything token-shaped
make clean
```

Pull requests run `make scan`, `make test`, a Release build and the App Store
build on macOS 15 and macOS 26.

### Preflight checks — the tests

The tests never reach GitHub and never touch your Keychain. `StubGitHub`
stands in for the API, so the client's caching and rate-limit handling and the
model's behaviour — a revoked token, a laptop going offline, a merge GitHub
refuses — are exercised against scripted responses. This matters more than
usual here: the tests run hosted inside the app, so a test that signed out for
real would delete the token of whoever ran it. Token storage is injected for
exactly that reason.

To listen in on what the running app is doing:

```sh
log stream --predicate 'subsystem == "net.hlnd.Cleared"' --level debug
```

### The simulator — working on the panel

Laying out the board against live GitHub means waiting for a deployment to
actually be held — the rare event the whole app exists to catch. `make preview`
opens the panel in an ordinary window with fixtures covering the shapes that
matter: a title long enough to wrap, a gate spanning two environments, and
enough strips to push the queue past its height cap. It runs as a second
instance, so an installed copy keeps watching.

### Signing and the Keychain

GitCleared signs **ad-hoc** by default so anyone can clone and build without an
Apple account. The cost is that every rebuild produces a new app identity, which
invalidates the access list on the Keychain entry holding your token — so you
have to reconnect after each build. The connect screen says so when it detects
that case rather than pretending no token was ever saved.

To make the signature stable, copy `Local.xcconfig.example` to `Local.xcconfig`
(gitignored) and set an identity from `security find-identity -v -p codesigning`.
The file is optional: without it the build falls back to ad-hoc signing.

Install the pre-commit secret scan with `./Scripts/install-hooks.sh`.

### Departures — releasing

A build that other people can download has to be signed with a Developer ID
and notarized, or Gatekeeper refuses to open it:

```sh
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=gitcleared-notary \
make dist         # writes dist/GitCleared-<version>.zip
```

`NOTARY_PROFILE` is a credential profile saved once with
`xcrun notarytool store-credentials`. The script signs with the hardened
runtime, submits to Apple, staples the ticket and asks Gatekeeper to confirm
before it reports success.

### Mac App Store

The store requires the App Sandbox, so there is a third build configuration,
`AppStore`: Release plus `Resources/Cleared.entitlements` (the sandbox, and
outbound network access — nothing else). It is what the scheme archives with,
so in Xcode it is just **Product → Archive**, then **Distribute App → App Store
Connect**.

Set the team that will submit in `Local.xcconfig` first:

```
CLEARED_APPSTORE_TEAM = YOURTEAMID
CLEARED_APPSTORE_IDENTITY = Apple Development
```

It can be a different team from the one that signs your day-to-day builds. That
team's Apple ID has to be signed in under Xcode → Settings → Accounts; Xcode
then registers the bundle ID and creates the provisioning profile itself.

From the command line, `make appstore` does the same archive, exports the
signed package to `dist/appstore/`, and checks that the app inside is sandboxed
and signed for distribution. It uploads nothing. The archive is written where
Xcode's Organizer looks, so you can upload that same build from
**Window → Organizer**.

What differs in the sandboxed build:

- No *Use my gh CLI login* — a pasted token is the only way to connect.
- Its token is kept under a separate Keychain entry from a direct build's. The
  two are signed differently and could not read each other's entry anyway;
  separate names mean neither ever triggers a Keychain prompt for the other's.
- Its settings live in the app's sandbox container, so they start fresh.

`make appstore-build` builds that configuration without archiving and needs no
signing set up. CI runs it on every pull request.

### Hangar layout

```
Sources/Cleared/
├── Auth/        Keychain wrapper, token store, gh CLI import
├── GitHub/      Actor-isolated client (ETag cache, rate limits), the four
│                clearances, and the reader for workflow_dispatch inputs
├── Models/      Sendable value types
├── Queue/       AppModel — the polling loop, actions, banner state
├── Support/     Settings, notifications, launch at login, logging
└── UI/          MenuBarExtra panel
```

Built with SwiftUI `MenuBarExtra`, Swift 6 strict concurrency, and no third-party
dependencies.

## License

MIT — see [LICENSE](LICENSE).

GitCleared is an independent project. It is not affiliated with, endorsed by or
sponsored by GitHub, the Git project or Software Freedom Conservancy.
