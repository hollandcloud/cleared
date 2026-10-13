# Privacy Policy — GitCleared

_Last updated: 13 October 2026_

GitCleared has no accounts of its own, no server, and no analytics. This policy
is short because there is very little to describe.

## What leaves your Mac

**Requests to GitHub, as you.** GitCleared talks to one service:
**api.github.com**. It asks GitHub which of your deployments are waiting for
approval, which of your pull requests are open, and which workflow runs have
failed. When you press a button it tells GitHub to approve or reject a
deployment, merge a pull request, re-run failed jobs, or start a workflow.

Every one of those requests is made directly from your Mac to GitHub over
HTTPS, authenticated with the access token you gave the app. We never see
them. GitHub handles them under its own privacy statement, as it does when you
use github.com.

Nothing is sent anywhere else. There is no server of ours for it to go to.

## What stays on your Mac

- **Your GitHub token**, in the macOS Keychain. It is never written to disk in
  the clear and never logged. *Settings → Disconnect and forget token* deletes
  it.
- **Your settings** — how often to check, which repositories to ignore or pin,
  your notification choices — in the app's preferences.
- **Diagnostic log lines**, in the system log on your Mac, where repository
  names are marked private. They are not sent to us or to anyone.

## What we do not do

No analytics. No crash reporting. No advertising. No tracking across apps or
websites. No third-party SDKs of any kind — the app is built on Apple's
frameworks alone, and its source is public.

## Notifications

If you allow them, GitCleared shows a notification when a deployment starts
waiting on you. They are created on your Mac. Nothing is sent to a push
service.

## Children

GitCleared is a tool for software developers and is not directed at children.
It collects no personal information from anyone.

## Changes

If this policy changes, the new version will be published at this address with
a new date, and the change will be visible in the repository's history.

## Contact

Questions about this policy: open an issue at
https://github.com/hollandcloud/cleared/issues

GitCleared is an independent project and is not affiliated with GitHub.
