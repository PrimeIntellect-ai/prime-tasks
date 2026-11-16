<Call> layout block component
[Calls API](https://api.slack.com/apis/calls) provides a way for call app to tell Slack the calling. In the context of Block Kit, [the `call` type for block element](https://api.slack.com/apis/calls#3._post_the_call_to_channel) has been available.

We will consider to add `<Call>` layout block to support indicating the call by your app.

```jsx
<Blocks>
  <Section>
    <a href="@U1234567890" />, you've got a call!
  </Section>
  <Call callId="R123" />
</Blocks>
```

The above JSX will transform into following:

```json
[
  {
    "type": "section",
    "text": {
      "type": "mrkdwn",
      "text": "<@U1234567890>, you've got a call!",
      "verbatim": true
    }
  },
  {
    "type": "call",
    "call_id": "R123"
  }
]
```

[![](https://user-images.githubusercontent.com/3993388/82516507-e7b2c680-9b55-11ea-8561-117819b2fc3c.jpeg)](https://api.slack.com/tools/block-kit-builder?mode=message&blocks=%5B%7B%22type%22%3A%22section%22%2C%22text%22%3A%7B%22type%22%3A%22mrkdwn%22%2C%22text%22%3A%22%3C%40U1234567890%3E%2C%20you%27ve%20got%20a%20call!%22%2C%22verbatim%22%3Atrue%7D%7D%2C%7B%22type%22%3A%22call%22%2C%22call_id%22%3A%22R123%22%7D%5D)

> **NOTE**: `<Call>` is available only in `<Blocks>` container as same as `<File>` layout block.

### Additional contract requirements

- `block_id` is optional: when neither `id` nor `blockId` is supplied, the rendered `call` block must omit the `block_id` field entirely, so the output is exactly `{ "type": "call", "call_id": "<callId>" }`.
