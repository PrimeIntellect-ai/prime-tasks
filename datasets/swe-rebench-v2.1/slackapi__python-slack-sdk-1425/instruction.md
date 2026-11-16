Add file input block element support
Refer to https://api.slack.com/reference/block-kit/block-elements#file_input for details. Only `slack_sdk.models` module needs updates for this feature.

### Category (place an `x` in each of the `[ ]`)

- [ ] **slack_sdk.web.WebClient (sync/async)** (Web API client)
- [ ] **slack_sdk.webhook.WebhookClient (sync/async)** (Incoming Webhook, response_url sender)
- [x] **slack_sdk.models** (UI component builders)
- [ ] **slack_sdk.oauth** (OAuth Flow Utilities)
- [ ] **slack_sdk.socket_mode** (Socket Mode client)
- [ ] **slack_sdk.audit_logs** (Audit Logs API client)
- [ ] **slack_sdk.scim** (SCIM API client)
- [ ] **slack_sdk.rtm** (RTM client)
- [ ] **slack_sdk.signature** (Request Signature Verifier)

### Requirements

Please read the [Contributing guidelines](https://github.com/slackapi/python-slack-sdk/blob/main/.github/contributing.md) and [Code of Conduct](https://slackhq.github.io/code-of-conduct) before creating this issue or pull request. By submitting, you are agreeing to those rules.

### Additional contract requirements

Expose the file input model through the public Python class name `FileInputElement`. It must support the configuration fields and serialization described for Slack's `file_input` block element, including `action_id`, `filetypes`, and `max_files`. Reject an `action_id` longer than the element's documented 255-character limit.
