Do we have an option to mention user groups instead of users in slack integrations?
### Discussed in https://github.com/test-results-reporter/reporter/discussions/163

<div type='discussions-op-text'>

<sup>Originally posted by **akhilaananthkumar** April  5, 2024</sup>
```json
{
  "name": "mentions",
  "inputs": {
    "users": [
      {
        "name": "Jon",
        "slack_uid": "ABCDEFGH"
      }
    ]
  }
}
```

Instead of using **member id** value in slack_uid  field, is there a way to use **group id**?

Slack group id - https://slack.com/intl/en-au/help/articles/212906697-Create-a-user-group</div>

### Additional contract requirements

- For Slack mentions, accept a group ID in the `slack_gid` field and format it as `<!subteam^GROUP_ID>`.
- When `slack_gid` is `here`, format the Slack mention as `<!here>`.
