# Age rating answers

App Store Connect → the app → **Age Rating**. Target: **4+**.
`Scripts/asc.py agerating` sends these.

Every content question is answered **None** / **No**. The app shows the state of
software deployments and pull requests, and has no other content.

| Question | Answer |
|---|---|
| Violence, of any kind | None |
| Profanity or crude humour | None |
| Mature or suggestive themes | None |
| Sexual content or nudity | None |
| Horror or fear themes | None |
| Medical or treatment information | None |
| Alcohol, tobacco or drug use or references | None |
| Simulated gambling | None |
| Contests | None |
| Gambling | No |
| Unrestricted web access | No |
| User-generated content | No |
| Messaging and chat | No |
| Advertising | No |

On "unrestricted web access": the app opens links to github.com in the user's
own browser. It has no web view of its own, which is what the question is
about.

On "user-generated content": pull request titles and workflow names are shown,
and they are written by people — but they are the user's own repositories'
content, fetched with the user's own credentials. The app has no feed, no
discovery and no way to see anyone else's content.
