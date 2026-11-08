Add support for pull_request_target webhook event
GitHub API documentation:
https://docs.github.com/en/actions/reference/events-that-trigger-workflows#pull_request_target

As mentioned in #1619, this webhook event needs to be supported.

This would be a great PR for any new contributor to this repo or a new Go developer.
All contributions are greatly appreciated!

Feel free to volunteer for any issue and the issue can be assigned to you so that others don't attempt to duplicate the work.

Please check out our [CONTRIBUTING.md](https://github.com/google/go-github/blob/master/CONTRIBUTING.md) guide to get started.

Thank you!

### Additional contract requirements

- Recognize the `pull_request_target` webhook event when parsing webhooks and expose its payload as a public `PullRequestTargetEvent` model, with JSON decoding consistent with other webhook payloads.
- Represent the event data for action, before and after commits, assignee, changes, installation, label, pull-request number, organization, pull request, repository, requested reviewer, requested team, and sender.
- Provide nil-safe accessors `GetAction`, `GetAfter`, `GetAssignee`, `GetBefore`, `GetChanges`, `GetInstallation`, `GetLabel`, `GetNumber`, `GetOrganization`, `GetPullRequest`, `GetRepo`, `GetRequestedReviewer`, `GetRequestedTeam`, and `GetSender`. Return the zero value for absent scalar data and nil for absent pointer data.
