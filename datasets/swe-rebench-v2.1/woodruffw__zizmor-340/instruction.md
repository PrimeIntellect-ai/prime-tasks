[BUG]: couldn't parse expression: fromJson(...)
### Pre-submission checks

- [X] I am **not** filing a feature request. These should be filed via the feature request form instead.
- [X] I have looked through the [open issues](https://github.com/woodruffw/zizmor/issues?q=is%3Aissue+is%3Aopen+) for a duplicate report.

### Expected behavior

I ran zizmor on https://github.com/nedbat/coveragepy/blob/master/.github/workflows/publish.yml.  Previous versions worked fine, but 0.10.0 produced a warning.

### Actual behavior

```
2024-12-19T19:16:32.907128Z  WARN audit:audit{workflow=file:///Users/ned/coverage/trunk/.github/workflows/publish.yml}: zizmor::audit::template_injection: couldn't parse expression: fromJson(steps.runs.outputs.data).workflow_runs[0].id
```

### Reproduction steps

- Clone https://github.com/nedbat/coveragepy
- Run zizmor on it.

### Logs

```plain text
% ~/.cargo/bin/zizmor --verbose coverage/trunk/.github/workflows/publish.yml
2024-12-20T12:10:22.028500Z DEBUG zizmor::state: using cache directory: "/Users/ned/.cache/zizmor"
2024-12-20T12:10:22.029274Z DEBUG zizmor::config: no config discovered; loading default
2024-12-20T12:10:22.029285Z DEBUG zizmor::config: loaded config: Config { rules: {} }
2024-12-20T12:10:22.036755Z  WARN audit:audit{workflow=file:///Users/ned/coverage/trunk/.github/workflows/publish.yml}: zizmor::audit::template_injection: couldn't parse expression: fromJson(steps.runs.outputs.data).workflow_runs[0].id
2024-12-20T12:10:22.046189Z  INFO audit: zizmor: 🌈 completed /Users/ned/coverage/trunk/.github/workflows/publish.yml
No findings to report. Good job!
```
```


### Additional context

_No response_

### Additional contract requirements

- When auditing the workflow expression `fromJson(steps.runs.outputs.data).workflow_runs[0].id`, zizmor must parse it successfully rather than report a parse failure.
