slack_sdk.models.blocks.Option's "description" value is invalid in blocks
The `description` value in `slack_sdk.models.blocks.Option` class has been invalid. The values must be an `plain_text` typed text object. However, the current implementation embeds the values as a string value in JSON payloads.

See also: https://api.slack.com/reference/block-kit/composition-objects#option

Thanks a lot for reporting this:
https://twitter.com/notmatt/status/1378092778379341826

### Reproducible in:

```python
option = Option(
    text="*this is plain_text text*",
    value="value-0",
    description="The most important choice!"
)
```

#### The Slack SDK version

Any versions

#### Python runtime version

Any versions

#### OS info

Any

### Expected result:

```json
{
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "test"
      },
      "accessory": {
        "type": "static_select",
        "placeholder": {
          "type": "plain_text",
          "text": "Select an item"
        },
        "options": [
          {
            "text": {
              "type": "plain_text",
              "text": "*this is plain_text text*"
            },
            "value": "value-0",
            "description": {
              "type": "plain_text",
              "text": "The most important choice!"
            }
          }
        ],
        "action_id": "static_select-action"
      }
    }
  ]
}
```

### Actual result:

```json
{
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "test"
      },
      "accessory": {
        "type": "static_select",
        "placeholder": {
          "type": "plain_text",
          "text": "Select an item"
        },
        "options": [
          {
            "text": {
              "type": "plain_text",
              "text": "*this is plain_text text*"
            },
            "value": "value-0",
            "description": "The most important choice!"
          }
        ],
        "action_id": "static_select-action"
      }
    }
  ]
}
```

### Requirements

For general questions/issues about Slack API platform or its server-side, could you submit questions at https://my.slack.com/help/requests/new instead. :bow:

Please read the [Contributing guidelines](https://github.com/slackapi/python-slack-sdk/blob/main/.github/contributing.md) and [Code of Conduct](https://slackhq.github.io/code-of-conduct) before creating this issue or pull request. By submitting, you are agreeing to those rules.
