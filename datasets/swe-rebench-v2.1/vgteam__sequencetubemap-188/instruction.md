CopyLink: Use [HIDDEN] [HIDDEN]
CopyLink does not work if HTTPS is used for the the app. The protocol is missing.

I created a pull request #184

### Additional contract requirements

- A copied link must use the current page’s origin, including its protocol, so that the link works when the app is served over HTTPS.
