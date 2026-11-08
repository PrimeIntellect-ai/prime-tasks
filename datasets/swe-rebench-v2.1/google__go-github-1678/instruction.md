Webhook payload fields for Github Apps: action, organization and installation
Each webhook event payload contains properties unique to the event. There are a few common keys for these properties: `action`, `sender`, `repository`, `organization`, `installation`.
more details: [Webhook payload object common properties](https://docs.github.com/en/free-pro-team@latest/developers/webhooks-and-events/webhook-events-and-payloads#webhook-payload-object-common-properties).

`WebHookPayload` struct doesn't contain `action`, `organization` and `installation` fields yet, but these objects need for webhooks from Github App.

Can I add these objects to `WebHookPayload`?

### Additional contract requirements

`WebHookPayload` must expose the action, organization, and installation properties as fields with the Go identifiers `Action`, `Organization`, and `Installation`. These fields must map to the webhook JSON properties `action`, `organization`, and `installation` respectively, so that a webhook payload can represent those values.
