SlackClient missing Web API methods
### Description

Describe your issue here.

### What type of issue is this? (place an `x` in one of the `[ ]`)
- [x] bug
- [ ] enhancement (feature request)
- [ ] question
- [ ] documentation related
- [ ] testing related
- [ ] discussion

### Requirements (place an `x` in each of the `[ ]`)
* [x ] I've read and understood the [Contributing guidelines](https://github.com/slackapi/python-slackclient/blob/master/.github/contributing.md) and have done my best effort to follow them.
* [ ] I've read and agree to the [Code of Conduct](https://slackhq.github.io/code-of-conduct).
* [ ] I've searched for any related issues and avoided creating a duplicate issue.

---

### Bug Report

Filling out the following details about bugs will help us solve your issue sooner.
The following methods are not available in the python API client.

https://api.slack.com/methods/admin.apps.approved.list
https://api.slack.com/methods/admin.apps.restricted.list
https://api.slack.com/methods/admin.conversations.setTeams
https://api.slack.com/methods/admin.emoji.add
https://api.slack.com/methods/admin.emoji.addAlias
https://api.slack.com/methods/admin.emoji.list
https://api.slack.com/methods/admin.emoji.remove
https://api.slack.com/methods/admin.emoji.rename
#### Reproducible in:

slackclient version: 2.5.0

python version: 3.7

### Additional contract requirements

The Python API client exposes `WebClient.admin_apps_approved_list(**kwargs)` and `WebClient.admin_apps_restricted_list(**kwargs)` for the `admin.apps.approved.list` and `admin.apps.restricted.list` endpoints, respectively.

The Python API client also exposes these operations, each dispatching to the endpoint with the matching name:

- `WebClient.admin_conversations_setTeams(**kwargs)` for `admin.conversations.setTeams`
- `WebClient.admin_emoji_add(**kwargs)` for `admin.emoji.add`
- `WebClient.admin_emoji_addAlias(**kwargs)` for `admin.emoji.addAlias`
- `WebClient.admin_emoji_list(**kwargs)` for `admin.emoji.list`
- `WebClient.admin_emoji_remove(**kwargs)` for `admin.emoji.remove`
- `WebClient.admin_emoji_rename(**kwargs)` for `admin.emoji.rename`

The following public methods must be available on `slack.WebClient`:

- `admin_teams_settings_info(team_id: str, **kwargs)` queries the `admin.teams.settings.info` endpoint for a workspace's settings.
- `admin_teams_settings_setDefaultChannels(*, team_id: str, channel_ids: List[str], **kwargs)` updates the default channels of a workspace through the `admin.teams.settings.setDefaultChannels` endpoint.
- `admin_teams_settings_setDiscoverability(*, team_id: str, discoverability: str, **kwargs)` updates a workspace's discovery setting through the `admin.teams.settings.setDiscoverability` endpoint.

Each of these methods raises an error when the Slack API responds with an error.
