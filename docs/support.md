# Support

Thanks for using GitCleared. This page is the support contact for the App Store
listing.

## Getting help or reporting a bug

Open an issue: **https://github.com/hollandcloud/cleared/issues**

It helps to include:

- Your macOS version, and whether you have the App Store version or one built
  from source
- What was on the panel — Holding, Ready to merge, In flight, Failed
- What you expected instead
- The line at the bottom of the panel, if it was reporting a problem

Please do not paste a token into an issue. GitCleared never needs you to.

## Things that are expected behaviour

**There is no Dock icon and no window.** GitCleared lives in the menu bar. Click
its icon there to open the panel; Quit is the power button at the bottom, or
Command-Q while the panel is open.

**The App Store version has no "Use my gh CLI login" button.** It runs in the
App Sandbox, which does not let it read a login from GitHub's command-line
tool. Paste a personal access token instead — *Create a token on GitHub…* opens
the right page with the scope selected.

**A pull request with green checks has no Merge button.** GitCleared only
offers Merge when GitHub would accept it. The row says why it isn't: *needs
review*, *behind base branch*, *conflicts*, *blocked by branch rules*. A pull
request with no checks at all is also not offered, because a pull request whose
checks simply have not started yet looks identical.

**A deployment is waiting on GitHub but not shown.** Only gates *you* can
approve are listed. A deployment waiting on someone else is not something you
can clear. It can also take up to two minutes to appear while the panel is
closed; opening the panel checks immediately.

**It says "Rate limited".** GitHub asked the app to pause. It will resume on its
own at the time shown and sends nothing until then.

**It went back to the connect screen.** GitHub rejected the token — it was
revoked or has expired. Connect again with a new one.

**An organization's repositories are missing.** Organizations that enforce
single sign-on need the token authorized for that organization on GitHub.

## Which token it needs

A classic token with the **repo** scope, or a fine-grained token limited to the
repositories you choose with these permissions: Actions (read and write),
Deployments (read and write), Contents (read and write), Pull requests (read).

## Privacy

See the [privacy policy](privacy.md). In short: the app talks only to GitHub,
as you, and nothing is sent to us.
