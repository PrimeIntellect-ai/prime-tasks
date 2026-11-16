please expose `slackApiUrl`
as mentioned here https://tools.slack.dev/node-slack-sdk/web-api/#custom-api-url
one can customize slack API URL like `options.slackApiUrl = 'http://localhost:8888/api/';`
this is not exposed in the action yet

addition in this area https://github.com/slackapi/slack-github-action/blob/main/src/client.js#L27

please do

### Additional contract requirements

- The action accepts an optional input named `api`: a custom Slack API URL to send Slack API method requests to.
- The configuration gathered from the action inputs exposes the provided `api` value.
- When an `api` value is provided, Slack API method requests are sent to that URL by passing it as the `slackApiUrl` option of the Slack Web API client.
