Auto detect the job in reusable workflow
**Is your feature request related to a problem? Please describe.**
In reusable workflow, action-slack cannot find job from [job list of current run](https://github.com/8398a7/action-slack/blob/v3.12.0/src/fields.ts#L141-L145). So field `job` and `took` are not available.

![image](https://user-images.githubusercontent.com/7571111/148557364-2e74f0ae-9622-467c-a66b-124b4e5ab892.png)

<details>
<summary>Example workflow</summary>

Reusable workflow
```yaml
# reusable workflow
name: shared-greet-and-notify
on:
  workflow_call:
    secrets:
      SLACK_WEBHOOK_URL
jobs:
  greet-and-notify:
    runs-on: ubuntu-latest
    steps:
      - name: greet
        run: echo hello
      - name: notify
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          fields: repo,took,workflow,job,ref,message
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
        if: always()
```

Actual workflow
```yaml
# using the reusable workflow
name: call-reusable
on: [push]
jobs:
  greeting:
    uses: owner/repo/.github/workflows/shared-greet-and-notify.yml@main
    secrets:
      SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```
</details>

In reusable workflow's job, `github.job` is the job name defined in the reusable workflow. But the format of job name in API response is `"<caller-job> / <callee-job>"`
(In abobe example, `github.job` is `"something-and-notify"` and job name in the response is `"greeting / greet-and-notify"`)

**Describe the solution you'd like**
I want the job to be detected in the same way as a normal workflow.
[HIDDEN]
If this seems good, I'll create PR.

**Describe alternatives you've considered**
There are available by passing caller's job name via `inputs` and setting `job_name`. but it is very redundancy.

<details>
<summary>Example</summary>

```yaml
name: shared-greet-and-notify
on:
  workflow_call:
    inputs:
      caller:
        type: string
        required: true
    secrets:
      SLACK_WEBHOOK_URL
jobs:
  greet-and-notify:
    runs-on: ubuntu-latest
    steps:
      - name: greet
        run: echo hello
      - name: notify
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          fields: repo,took,workflow,job,ref,message
          job_name: ${{ inputs.caller }} / greet-and-notify
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
        if: always()
```

```yaml
name: call-reusable
on: [push]
jobs:
  greeting:
    uses: owner/repo/.github/workflows/shared-greet-and-notify.yml@main
    with:
      caller: greeting # unfortunately, cannot using ${{ github.job }} in here
    secrets:
      SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```
</details>

**Additional context**
N/A

### Additional contract requirements

- In a reusable workflow, identify the current job when its job-list name is `<caller-job> / <callee-job>` and the current job name is `<callee-job>`. The `job` and `took` fields should then be available as they are for a normal workflow.
