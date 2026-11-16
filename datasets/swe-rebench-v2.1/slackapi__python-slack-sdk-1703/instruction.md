When will Elevate APIs be added to SDK?
The Sales Elevate APIs are documented, but they do not exist in the most up-to-date SDK version. In each of the following links, we see something like `app.client.admin_conversations_createForObjects` but when looking into the [client file](https://github.com/slackapi/python-slack-sdk/blob/main/slack_sdk/web/client.py), we don't see it.

- https://api.slack.com/methods/admin.conversations.createForObjects
- https://api.slack.com/methods/admin.conversations.linkObjects
- https://api.slack.com/methods/admin.conversations.unlinkObjects

#### The Slack SDK version

slack_sdk==3.35.0

### Requirements

For general questions/issues about Slack API platform or its server-side, could you submit questions at https://my.slack.com/help/requests/new instead. :bow:

Please read the [Contributing guidelines](https://github.com/slackapi/python-slack-sdk/blob/main/.github/contributing.md) and [Code of Conduct](https://slackhq.github.io/code-of-conduct) before creating this issue or pull request. By submitting, you are agreeing to those rules.

### Additional contract requirements

Add the following public methods to the Web API clients `slack_sdk.web.WebClient`, `slack_sdk.web.legacy_client.LegacyWebClient`, and `slack_sdk.web.async_client.AsyncWebClient`:

- `admin_conversations_createForObjects(*, object_id: str, salesforce_org_id: str, invite_object_team: Optional[bool] = None, **kwargs)` calls the `admin.conversations.createForObjects` endpoint.
- `admin_conversations_linkObjects(*, channel: str, record_id: str, salesforce_org_id: str, **kwargs)` calls the `admin.conversations.linkObjects` endpoint.
- `admin_conversations_unlinkObjects(*, channel: str, new_name: str, **kwargs)` calls the `admin.conversations.unlinkObjects` endpoint.

Each method forwards its named parameters and any additional keyword arguments to the Slack API. When `invite_object_team` is supplied, its value is forwarded to the API. For `AsyncWebClient`, errors returned by the Slack API are raised as `slack_sdk.errors.SlackApiError`.
