# App Review notes

Paste the block below into **App Review Information → Notes**, or run
`Scripts/asc.py review`, which sends it. The demo account fields stay empty:
there is no username and password. The app signs in with a GitHub token, which
goes in the notes — **replace the placeholder on the TOKEN line before
submitting** (see "What still needs you" in `Store/README.md`).

---

GitCleared is a menu bar app. It has no Dock icon and no main window. After
launch, look at the right-hand side of the menu bar for its icon and click it
to open the panel.

SIGNING IN. The app works against a GitHub account, so it needs a GitHub
personal access token. One for a test account is below. On first launch the
panel shows "Connect with a personal access token": paste the token into the
field and click Connect.

TOKEN: <replace with a token for the review account before submitting>

WHAT YOU SHOULD SEE. Once connected, the panel lists what is waiting on that
account, in this order:

• Holding — a deployment waiting at an environment gate, with a Clear button.
  Clicking Clear approves the deployment on GitHub.
• Ready to merge — an open pull request whose checks have passed, with a Merge
  button.
• In flight — open pull requests that cannot be merged yet, each with the
  reason.
• Failed — recent failed workflow runs, each with a Re-run button.

If the test account has nothing waiting, the panel shows "All clear". That is
the normal resting state, not an error.

OTHER CONTROLS, along the bottom of the panel: refresh, start a workflow (the
play icon — choose a repository, then a workflow), Settings (the gear, or
Command-comma), and Quit (the power icon, or Command-Q). Right-clicking a row
offers Open on GitHub and Copy Link, and on a held deployment, Reject.

NOTIFICATIONS. The app asks for notification permission after connecting. It
uses them only to say that a deployment has started holding. Declining changes
nothing else.

LAUNCH AT LOGIN is off by default and is only turned on by the switch in
Settings.

WHY THERE IS NO "USE MY GH CLI LOGIN" BUTTON. The version on GitHub can import
a login from GitHub's command-line tool. This version runs in the App Sandbox,
which does not allow that, so a pasted token is the only way to sign in.

The app talks only to api.github.com. It has no server of its own, no
analytics and no advertising.

---

## What the reviewer needs that only the owner can provide

A token. GitHub tokens cannot be created through the API, and one for a
personal account should not be handed to App Review. The practical route:

1. Create a throwaway GitHub account for review, or use an existing test one.
2. Give it one repository with an environment that requires that account as a
   reviewer, a workflow that deploys to it, and an open pull request with a
   passing check — so there is something Holding and something Ready to merge.
3. Create a fine-grained token scoped to that repository only, with Actions,
   Deployments, Contents (read and write) and Pull requests (read).
4. Put it on the TOKEN line above and run `Scripts/asc.py review`.

Revoke the token once the review is over.
