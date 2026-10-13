# Cleared

**Clear held deploys and green pull requests from the macOS menu bar.**

Cleared is the *write* half of a GitHub menu bar app. The excellent read-only
monitors — RepoBar, PullBar, GitBar, Deplog — all tell you something needs your
attention and then send you to a browser tab. Cleared gives you the button.

It does four things and nothing else:

| | Action | GitHub API |
|---|---|---|
| ▲ | **Clear a held deployment** — approve an environment gate you're a required reviewer on | `POST /actions/runs/{id}/pending_deployments` |
| ● | **Merge a green PR** — squash-merge when checks pass and nothing conflicts | `PUT /pulls/{n}/merge` |
| ✖ | **Re-run failed jobs** | `POST /actions/runs/{id}/rerun-failed-jobs` |
| ▶ | **Start a workflow** by hand | `POST /actions/workflows/{id}/dispatches` |

The queue is sorted by what blocks you, not by repository. A held production
deploy is the top item no matter which repo it's in, because that's the one
that costs real time.

Every button is one GitHub would honour. A pull request only gets **Merge** when
its checks are green *and* GitHub reports no review or branch rule in the way,
and the merge is pinned to the commit Cleared last saw — so a push that lands
between polls is refused, not merged unseen. **Start a workflow** lists only
workflows that declare `workflow_dispatch`, with the inputs each one's file
declares.

## Why it exists

Environment gates with required reviewers don't fail — they idle. A deploy sits
in `waiting` until the one person named as a reviewer happens to look at the
right browser tab. Measured across a month of one heavy user's repositories,
the median gated deploy waited over half an hour to start; the worst sat for
eight days. Nothing was broken. Nobody was looking.

Cleared puts that queue in the menu bar and makes clearing it one click.

## Install

Requires macOS 14+, and Xcode 16+ with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) to build. There is no signed download yet, so for now
Cleared is built from source:

```sh
git clone https://github.com/hollandcloud/cleared.git
cd cleared
make install      # builds Release, copies it to /Applications, launches it
```

Then turn on *Settings → Launch at login*. Cleared starts watching as soon as it
launches — you don't need to open the panel for holds to be noticed.

`make run` builds and launches without installing, which is fine for a look
but can't be registered to launch at login.

Or open it in Xcode:

```sh
make generate     # writes Cleared.xcodeproj from project.yml
open Cleared.xcodeproj
```

`Cleared.xcodeproj` is generated and deliberately not committed — `project.yml`
is the source of truth.

## Connecting

Cleared needs a GitHub token with the **`repo`** scope.

- **If you use the `gh` CLI:** click *Use my gh CLI login*. Cleared shells out to
  `gh auth token` once and stores the result.
- **Otherwise:** paste a personal access token. *Create a token on GitHub…*
  opens the new-token page with the scope already selected.

The Mac App Store version only offers the second. It runs in the App Sandbox,
which lets it neither run `gh` nor read the login `gh` keeps.

The token is written to your login Keychain under `net.hlnd.Cleared` and read
back per request. It is never written to `UserDefaults`, never written to disk
in the clear, and never logged — the only representation Cleared will ever
display is a fingerprint like `ghp_…2345 · 40 chars`.

To revoke: *Settings → Disconnect and forget token*, which deletes the Keychain
item. Revoke the token itself on GitHub. If GitHub starts rejecting the token —
revoked, or expired — Cleared stops polling and returns to the connect screen
saying so, rather than failing quietly.

### Why `repo`

Approving a deployment, merging, re-running jobs and dispatching a workflow all
require `repo` on a classic token; GitHub offers nothing narrower. (`workflow`
is not needed — that scope is for editing workflow files, which Cleared never
does.)

If that's more access than you want a menu bar app to hold, use a fine-grained
token limited to the repositories you want Cleared to touch, with these
repository permissions:

| Permission | Access | Used for |
|---|---|---|
| Actions | Read and write | Listing runs, re-running jobs, starting workflows |
| Deployments | Read and write | Approving or rejecting a held deployment |
| Contents | Read and write | Merging; reading workflow files for their inputs |
| Pull requests | Read | Listing your open pull requests |

Organizations that enforce SAML single sign-on also need the token authorized
for that organization on GitHub.

## Using it

- **Click a row** to open it on GitHub. **Right-click** for *Copy Link* — and,
  on a held deployment, *Reject…*, which cancels the waiting jobs with a reason.
- **⌘1–⌘9** merge the first nine ready pull requests, in the order shown.
  **⌘R** refreshes, **⌘,** opens Settings, **⌘Q** quits.
- A **notification** appears when a deployment starts holding, with a *Clear*
  button on it. It is withdrawn once the hold is gone, whoever cleared it.
- *Settings → Ask before clearing or merging* turns each button into a
  two-click *Sure?* confirmation. It is off by default: one click is the point.
- Pull requests that can't be merged yet sit under **In flight** with the
  reason — *needs review*, *checks running*, *behind base branch*, *conflicts*.

## How it stays inside the rate limit

Polling every repository every 30 seconds would burn 5,000 requests an hour on
its own. Cleared avoids that:

- **Conditional requests.** Every poll sends `If-None-Match`. GitHub does not
  charge a `304` against the hourly limit, and a repository with nothing
  waiting returns a byte-identical body forever — so a quiet repository is
  free.
- **One GraphQL query** covers open pull requests and their check rollups
  across every repository, rather than one REST call per repo.
- **Backoff.** Polling slows by 4× while the menu is closed, and by a further
  4× when fewer than 500 calls remain.
- **Stopping when told to.** If GitHub answers with a rate limit, Cleared sends
  nothing further on that budget until the time GitHub named, instead of
  retrying into it.

Remaining budget is shown in the footer. When a poll comes back short — no
network, rate limited — the footer says why and how stale the queue is.

## Repository discovery

Cleared ships with **no repository list**. On first connect it asks GitHub for
repositories you've pushed to in the last 90 days (configurable) and watches
the 20 most recent, re-checking hourly so a new repository is picked up without
a restart. In Settings you can ignore any of them (and un-ignore them later), or
pin a repository so it stays watched however long it has been quiet.

This is deliberate: it means the source of this public repository reveals
nothing about which repositories anyone actually tracks, and low-traffic repos
that see one PR a month get picked up without being added by hand.

## Development

```sh
make build                      # debug build
make test                       # unit tests
make install                    # Release build into /Applications
make appstore-build             # the sandboxed App Store configuration
make preview                    # render the panel against sample data
make preview FIXTURE=overflow   # ... with enough rows to scroll
make preview FIXTURE=empty      # ... the all-clear state
make icon                       # redraw the app icon from Scripts/make-icon.swift
make scan                       # refuse to commit anything token-shaped
make clean
```

Pull requests run the same `make scan`, `make test` and a Release build on
macOS 15 and macOS 26.

### Tests

The tests never reach GitHub and never touch your Keychain. `StubGitHub`
stands in for the API, so the client's caching and rate-limit handling and the
model's behaviour — a revoked token, a laptop going offline, a merge GitHub
refuses — are exercised against scripted responses. This matters more than
usual here: the tests run hosted inside the app, so a test that signed out for
real would delete the token of whoever ran it. Token storage is injected for
exactly that reason.

To watch what the running app is doing:

```sh
log stream --predicate 'subsystem == "net.hlnd.Cleared"' --level debug
```

### Working on the panel

Laying out the queue against live GitHub means waiting for a deployment to
actually be held — the rare event the whole app exists to catch. `make preview`
opens the panel in an ordinary window with fixtures covering the shapes that
matter: a title long enough to wrap, a gate spanning two environments, and
enough rows to push the queue past its height cap.

### Signing and the Keychain

Cleared signs **ad-hoc** by default so anyone can clone and build without an
Apple account. The cost is that every rebuild produces a new app identity, which
invalidates the access list on the Keychain entry holding your token — so you
have to reconnect after each build. The sign-in screen says so when it detects
that case rather than pretending no token was ever saved.

To make the signature stable, copy `Local.xcconfig.example` to `Local.xcconfig`
(gitignored) and set an identity from `security find-identity -v -p codesigning`.
The file is optional: without it the build falls back to ad-hoc signing.

Install the pre-commit secret scan with `./Scripts/install-hooks.sh`.

### Releasing

A build that other people can download has to be signed with a Developer ID
and notarized, or Gatekeeper refuses to open it:

```sh
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=cleared-notary \
make dist         # writes dist/Cleared-<version>.zip
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
signed package to `dist/appstore/Cleared.pkg`, and checks that the app inside
is sandboxed and signed for distribution. It uploads nothing. The archive is
written where Xcode's Organizer looks, so you can upload that same build from
**Window → Organizer**.

What differs in the sandboxed build:

- No *Use my gh CLI login* — a pasted token is the only way to connect.
- Its token is kept under a separate Keychain entry from a direct build's. The
  two are signed differently and could not read each other's entry anyway;
  separate names mean neither ever triggers a Keychain prompt for the other's.
- Its settings live in the app's sandbox container, so they start fresh.

`make appstore-build` builds that configuration without archiving and needs no
signing set up. CI runs it on every pull request.

### Layout

```
Sources/Cleared/
├── Auth/        Keychain wrapper, token store, gh CLI import
├── GitHub/      Actor-isolated client (ETag cache, rate limits), the four
│                verbs, and the reader for workflow_dispatch inputs
├── Models/      Sendable value types
├── Queue/       AppModel — the polling loop, actions, banner state
├── Support/     Settings, notifications, launch at login, logging
└── UI/          MenuBarExtra panel
```

Built with SwiftUI `MenuBarExtra`, Swift 6 strict concurrency, and no third-party
dependencies.

## License

MIT — see [LICENSE](LICENSE).
