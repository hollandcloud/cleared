# App Privacy answers

App Store Connect → the app → **App Privacy**. This questionnaire is answered in
the browser; the API does not accept it.

## Data collection

**Do you or your third-party partners collect data from this app? → No**

The reasoning, because it is a judgement call and the other answer is defensible:

- Apple counts data as collected when it is sent off the device *and* the
  developer or the developer's partners can access it beyond servicing the
  request.
- GitCleared sends requests to `api.github.com`, authenticated with a token the
  user supplies for **their own** GitHub account. Nothing is sent to the
  developer. There is no server, no analytics, no crash reporting and no
  advertising or attribution SDK in the app.
- GitHub is not the developer's partner here. It is the service the user
  already has an account with, and the app is a client for that account — the
  same position as a mail client talking to the user's own mail server.

So nothing is collected by "you or your third-party partners", and the label
reads **Data Not Collected**.

### If you would rather answer conservatively

weatherfeels answered "Yes" for the coordinate it sends to weather.gov, on the
reading that any transmission counts. Applying that reading here would mean
declaring:

| Data type | Used for | Linked to identity | Tracking |
|---|---|---|---|
| Identifiers → User ID (the GitHub account) | App Functionality | Yes | No |

That over-describes what happens — the developer never sees the account — but
it is the answer to give if a reviewer pushes back on "No".

## Things that are not collected, either way

Contact info, location, contacts, user content, browsing or search history,
usage data, diagnostics, purchases, financial or health data. The token itself
is stored in the macOS Keychain and is never written to disk in the clear or
logged.
