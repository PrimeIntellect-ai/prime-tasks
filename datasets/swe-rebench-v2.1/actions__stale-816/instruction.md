Problems since moving to v5 - action takes bot comment as a regular update
## Your stale action configuration

Config here -> https://github.com/asyncapi/bundler/blob/master/.github/workflows/stale-issues-prs.yml

```yml
name: Manage stale issues and PRs

on:
  schedule:
  - cron: "0 0 * * *"

jobs:
  stale:
    if: startsWith(github.repository, 'asyncapi/')
    name: Mark issue or PR as stale
    runs-on: ubuntu-latest
    steps:
    - uses: actions/stale@v5.1.0
      with:
        repo-token: ${{ secrets.GITHUB_TOKEN }}
        stale-issue-message: |
          This issue has been automatically marked as stale because it has not had recent activity :sleeping:

          It will be closed in 120 days if no further activity occurs. To unstale this issue, add a comment with a detailed explanation.

          There can be many reasons why some specific issue has no activity. The most probable cause is lack of time, not lack of interest. AsyncAPI Initiative is a Linux Foundation project not owned by a single for-profit company. It is a community-driven initiative ruled under [open governance model](https://github.com/asyncapi/community/blob/master/CHARTER.md).

          Let us figure out together how to push this issue forward. Connect with us through [one of many communication channels](https://github.com/asyncapi/community/issues/1) we established here.

          Thank you for your patience :heart:
        stale-pr-message: |
          This pull request has been automatically marked as stale because it has not had recent activity :sleeping:

          It will be closed in 120 days if no further activity occurs. To unstale this pull request, add a comment with detailed explanation.

          There can be many reasons why some specific pull request has no activity. The most probable cause is lack of time, not lack of interest. AsyncAPI Initiative is a Linux Foundation project not owned by a single for-profit company. It is a community-driven initiative ruled under [open governance model](https://github.com/asyncapi/community/blob/master/CHARTER.md).

          Let us figure out together how to push this pull request forward. Connect with us through [one of many communication channels](https://github.com/asyncapi/community/issues/1) we established here.

          Thank you for your patience :heart:
        days-before-stale: 120
        days-before-close: 120
        stale-issue-label: stale
        stale-pr-label: stale
        exempt-issue-labels: keep-open
        exempt-pr-labels: keep-open
        close-issue-reason: not_planned```
```

## Further context

One of examples is this issue -> https://github.com/asyncapi/bundler/issues/34
We run stale action every day.
So one day issue got stale label and comment from bot: https://github.com/asyncapi/bundler/runs/7602251973?check_suite_focus=true
But then, next day, it was "unstaled" with https://github.com/asyncapi/bundler/runs/7622201096?check_suite_focus=true

See the logs:
```
Checking for comments on issue since: 2022-08-01T00:00:42Z
Comments that are not the stale comment or another bot: 0
The stale label should not be removed
Remove the stale label since the issue has been updated and the workflow should remove the stale label when updated
```

I can't figure why it decided all suddenly to remove stale label.

Another example, from completely different repo, but with exactly the same configuration -> https://github.com/asyncapi/website/pull/659#issuecomment-1212612413

Issues noticed after moving from `v4.0.0` to `v5.1.0`

### Additional contract requirements

When the stale action's own comment is the only activity around stale labeling, a later run must not remove the stale label merely because the item's update timestamp differs from the stale-label timestamp by a second or two.
