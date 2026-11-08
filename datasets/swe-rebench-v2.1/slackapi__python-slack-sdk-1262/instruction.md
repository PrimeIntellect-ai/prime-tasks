blocks/attachments as str for chat.* API calls should be clearly supported
The use case reported at https://github.com/slackapi/python-slack-sdk/pull/1259#issuecomment-1237007209 has been supported for a long time but it was **not by design**.

```python
client = WebClient(token="....")
client.chat_postMessage(text="fallback", blocks="{ JSON string here }")
```

The `blocks` and `attachments` arguments for chat.postMessage API etc. are supposed to be `Sequence[Block | Attachment | dict]` as of today. However, passing the whole blocks/attachments as a single str should be a relatively common use case. In future versions, the use case should be clearly covered in both type hints and its implementation.

### Category (place an `x` in each of the `[ ]`)

- [x] **slack_sdk.web.WebClient (sync/async)** (Web API client)
- [ ] **slack_sdk.webhook.WebhookClient (sync/async)** (Incoming Webhook, response_url sender)
- [ ] **slack_sdk.models** (UI component builders)
- [ ] **slack_sdk.oauth** (OAuth Flow Utilities)
- [ ] **slack_sdk.socket_mode** (Socket Mode client)
- [ ] **slack_sdk.audit_logs** (Audit Logs API client)
- [ ] **slack_sdk.scim** (SCIM API client)
- [ ] **slack_sdk.rtm** (RTM client)
- [ ] **slack_sdk.signature** (Request Signature Verifier)

### Requirements

Please read the [Contributing guidelines](https://github.com/slackapi/python-slack-sdk/blob/main/.github/contributing.md) and [Code of Conduct](https://slackhq.github.io/code-of-conduct) before creating this issue or pull request. By submitting, you are agreeing to those rules.
