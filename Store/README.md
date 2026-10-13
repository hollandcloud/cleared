# App Store listing

Everything that goes on the Mac App Store page, plus the script that pushes it.
The layout and the script follow `hollandcloud/weatherfeels`. Read **Before you
submit** first: two things in it are decisions, not tasks.

```
Store/
  README.md                     this file
  metadata/
    en-US/                      one file per App Store Connect field
      name.txt                  30 char limit   — 10 used
      subtitle.txt              30              — 30
      promotional_text.txt      170             — 165
      keywords.txt              100             — 98
      description.txt           4000            — 2596
      release_notes.txt         4000            — what changed; ignored on a first version
      support_url.txt           docs/support.md in this repo
      privacy_policy_url.txt    docs/privacy.md in this repo
      marketing_url.txt         the repo itself
    review-notes.md             the block between the --- fences goes to App Review
    app-privacy.md              the App Privacy questionnaire answers
    age-rating.md               the age-rating questionnaire answers
  screenshots/
    raw/                        the panel, captured from the preview harness
    mac/      2880x1800         the same captures, framed and captioned
  review-contact.local.json     who App Review should call — gitignored, see below

docs/
  privacy.md                    the published privacy policy
  support.md                    the published support page
```

## Before you submit

**1. The name.** The app was renamed to GitCleared in 0.4.1. The Git trademark
policy (git-scm.com/about/trademark, section 2.3) says the mark may not be used
"as a syllable in a new word or as part of a portmanteau (e.g., 'Gitalicious',
'Gitpedia') used as a mark for a third-party product or service", and names
GitHub and GitLab as exceptions under their own licences. "GitCleared" is that
pattern. The form the policy allows without permission is "[Product Name] for
Git"; permission for anything else is asked of Software Freedom Conservancy.

Plenty of shipping products have names like this, so it may never matter. It is
written down here because App Review is where a trademark holder's complaint
lands, and because weatherfeels was renamed before submission for a comparable
reason. Changing course is cheap: the name comes from `PRODUCT_NAME` in
`project.yml` and `name.txt` here, and everything else follows — including the
wordmark on the screenshots, which `make screenshots` redraws.

**2. The reviewer needs a way in.** GitCleared does nothing until it has a GitHub
token, so App Review has to be given one. `metadata/review-notes.md` has a
placeholder on its TOKEN line and the steps for making a suitable token: a
throwaway account, one repository, a fine-grained token scoped to it. Submitting
with the placeholder still in place gets a rejection for "unable to sign in".

## What still needs you

| Thing | Why it is not done |
|---|---|
| The two decisions above | They are yours. |
| App Privacy answers | The questionnaire is browser-only. `metadata/app-privacy.md` has the answer and the reasoning. |
| Price set to Free | The description says free and open source. The pricing page has to agree. |
| Submitting for review | Deliberately left to a person. `Scripts/asc.py submit` exists for when you are ready. |

## Pushing it

```sh
export ASC_KEY_ID=…                    # the key for the team that owns the app record
export ASC_ISSUER_ID=<uuid>            # App Store Connect → Users and Access →
                                       # Integrations. Not stored in this repo.

Scripts/asc.py status                  # read-only. run this first, and again after.
Scripts/asc.py text                    # name, subtitle, description, keywords, URLs
Scripts/asc.py screenshots             # replaces the set rather than appending
Scripts/asc.py review                  # review contact and notes
Scripts/asc.py agerating               # the questionnaire, all answers "none"
Scripts/asc.py attach                  # point the version at the uploaded build
```

The key file is read from `~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8`.
It needs the `cryptography` Python package.

`text` overwrites whatever is in App Store Connect from the files here, name and
subtitle included. If you change either in the browser, copy it back into the
`.txt` first, or the next run reverts you.

**The review contact** — a name, a phone number and an email address — is read
from `Store/review-contact.local.json`, which is gitignored. Those belong to a
person and this repository is public. Create it once:

```json
{ "firstName": "…", "lastName": "…", "phone": "…", "email": "…" }
```

Builds go up with `make appstore` and Xcode's Organizer; this script only
handles the listing.

## How the screenshots were made

The App Store takes Mac screenshots at a few exact sizes, and a menu bar panel
is 420 points wide, so a raw capture cannot be used as it is. Each image here is
a real capture placed on a 2880x1800 canvas beside one line saying what it
shows.

- **The captures** come from the preview harness in its bare mode, which draws
  the panel against sample data with no window chrome:
  `open -n GitCleared.app --args --ui-preview full --bare`. The fixtures are
  `full`, `empty`, `connect` and `connect-appstore`. Settings and the workflow
  sheet are opened on top of `full` and captured with the panel dimmed behind
  them, as they appear in use.
- **Each window is captured by its ID** (`screencapture -l`), never the whole
  screen, so nothing else on the Mac can end up in a store image.
- **The frames** are drawn by `Scripts/compose-screenshots.swift` — `make
  screenshots` — which reads the captions from its own source and the app's name
  from `name.txt`.
- The repositories, pull requests and workflows shown are the sample data in
  `SampleData.swift`. Nothing in them is real.

If the panel's appearance changes, retake the captures in `raw/` and run `make
screenshots`, or the store page stops matching the app.
