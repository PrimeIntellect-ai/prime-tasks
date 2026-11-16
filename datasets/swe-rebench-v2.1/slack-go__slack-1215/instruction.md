OAuth Slack Token Logged In Clear
**Describe the bug**

While using Argo Event which leverage `slack-go/slack` for Slack triggers, it was noticed that the OAuth Slack token is logged in the clear. Specifically, https://github.com/slack-go/slack/blob/686c209f9525a78313cfe54cbc07cd86bd677384/chat.go#L217 is logging the whole API request resulting in also logging a clear version of the OAuth slack token in the log files. The following is an example:

```
sensor-qrlrb-58d497d595-q9dmh main 2020-11-09T10:11:50.147597554Z slack-go/slack2020/11/09 10:11:50 chat.go:217: Sending request: channel=random&text=webhook+triggered%21&token=xoxb-xxxx-xxx-xxx
```

**Expected behavior**

OAuth Slack token not never be logged in the clear in the log files.

_**Argo Events related issue:**_ https://github.com/argoproj/argo-events/issues/944

### Additional contract requirements

- In debug logs for `SendMessage`, the token `xtest-token-1234-abcd` must be logged as `token=xtest-REDACTED`, and the token `xoxe.xtest-token-1234-abcd` must be logged as `token=xoxe.xtest-REDACTED`.
- In the debug request log for `SendMessage`, retain the `text` form field unchanged: its value must match the original message text passed to `MsgOptionText`.
