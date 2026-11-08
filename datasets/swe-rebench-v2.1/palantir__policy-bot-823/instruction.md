has_successful_status may use incorrect check-run
It seems that there are situations where the github api can return multiple "latest" check-runs (for a given sha & check-run name) and policy-bot uses the least recent.

eg: I pushed this workflow:

```
on:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: |
          if [ $PR_NUMBER == '1' ]; then
            echo "First PR, failing"
            exit 1
          else
            echo "Passing"
            exit 0
          fi
        env:
          PR_NUMBER: ${{ github.event.pull_request.number }}
```

and opened PR 1. The job failed then I closed the PR.

Then I opened PR 2 and the job succeeds.

Looking at the query that I think policy-bot makes, there are 2 runs for `test` and I think policy-bot uses the last (least recent) one. Strangely both runs reference PR 2.

```
curl -L \
  -H "Accept: application/vnd.github.antiope-preview+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/<org>/<repo>/commits/c4bb5fb/check-runs?filter=latest \
    | jq '.check_runs[] | {name,completed_at,conclusion,pull_requests}'

{
  "name": "test",
  "completed_at": "2024-08-14T07:23:49Z",
  "conclusion": "success",
  "pull_requests": [
    {
      "number": 2,
      ...
    }
  ]
}
{
  "name": "test",
  "completed_at": "2024-08-14T07:22:49Z",
  "conclusion": "failure",
  "pull_requests": [
    {
      "number": 2,
      ...
    }
  ]
}
```

[HIDDEN] but I guess there can be other scenarios where the same commit has multiple "latest" check-runs

### Additional contract requirements

- When multiple latest check-runs exist for the same commit and check-run name, policy-bot must use the most recent result rather than an older result.
