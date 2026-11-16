maxSelectedItems attribute is no longer working
`maxSelectedItems` attribute for multiple select menu seems to no longer work.

`max_selected_items` field is still defined in [`@slack/types`](https://github.com/slackapi/node-slack-sdk/blob/95a561876d734c51d69824bf75cf8b64b57d6908/packages/types/src/index.ts#L134) and
Slack Block Kit Builder does not throw error even if defined `max_selected_items` in JSON, but the actual component ignores this restriction. In addition, all descriptions about `max_selected_items` field are removed from [the documentation of Slack API](https://api.slack.com/reference/block-kit/block-elements#multi_select).
