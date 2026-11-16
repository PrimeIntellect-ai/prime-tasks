False positive for the `excessive-permission` audit when there is a single job
### Pre-submission checks

- [X] I am **not** reporting a bug (crash, false positive/negative, etc). These must be filed via the bug report template.
- [X] I have looked through the open issues for a duplicate request.

### What's the problem this feature will solve?

The `excessive-permission` audit reports an error when write permissions are declared at the workflow level, suggesting to scope them at the job level. This is indeed sound advice if there are multiple jobs in the workflow. While scanning some repositories though, I noticed that the audit returns an high confidence error even when there is a single job:

```yaml
permissions:
  contents: write

jobs:
  single:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
```

In this case, as far as I know putting the permission at the workflow or at the job level should make no difference (as long as there is a single job). This is causing a fair amount of noise when analyzing a large number of workflows.

### Describe the solution you'd like

When there is a single job, the link should not report a high confidence error. It might still be useful to have this trigger at the pedantic level, as it's still cleaner to define the permissions for the job.

### Additional context

_No response_

### Additional contract requirements

- For a workflow with one job and workflow-level `contents: write` permissions, suppress the `excessive-permissions` finding by default. When invoked with `--pedantic`, report the finding with audit confidence `High`.
- For this case, default-mode output must be exactly `No findings to report. Good job! (1 suppressed)`.
