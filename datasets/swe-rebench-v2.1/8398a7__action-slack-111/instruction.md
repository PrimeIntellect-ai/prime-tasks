“Job is not found. Check the matrix.”
**Describe the bug**
About two weeks ago the job field of our Github Action reports in Slack changed to report “Job is not found. Check the matrix.” The Action configuration has not changed in that time. To our knowledge nothing related to the Github Action or our git workflow or team activity has changed.

**Expected behavior**
The expected behavior is the Slack message produced by the action to include the job name from the Githhub action configuration.

**Screenshots**
Here is a sample report in Slack before the behavior changed.
<img width="663" alt="Screen Shot 2020-09-03 at 12 04 40 PM" src="https://user-images.githubusercontent.com/1048550/92139949-7b936000-edde-11ea-8413-fdb52a3d82ad.png">

Here is a sample report in Slack after the behavior changed:
<img width="665" alt="Screen Shot 2020-09-03 at 12 04 12 PM" src="https://user-images.githubusercontent.com/1048550/92139947-7afac980-edde-11ea-969d-04a5dd13870b.png">

**Additional context**
Here is the config from our Github Action configuration:

```
- uses: 8398a7/action-slack@v3
  with:
    icon_emoji: ':octocat:'
    status: ${{ job.status }}
    fields: repo,author,eventName,workflow,job
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_CI_CHANNEL_WEBHOOK }}
  if: always() # Pick up events even if the job fails or is canceled.

```

### Additional contract requirements

- The optional `job_name` input can specify the configured job display name when it differs from the GitHub job identifier; the Slack job field must report that configured name.
- When a job is not found, the field value must be exactly `Job is not found.\nCheck <https://action-slack.netlify.app/fields|the matrix> or <https://action-slack.netlify.app/with#job_name|job name>.`, with a newline between the two sentences.
