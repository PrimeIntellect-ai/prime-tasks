Creator label too long.
## Summary

> Is there a way to prevent the Argo Workflow REST API from auto-generating/adding the workflows.argoproj.io/creator label? The label it generates for Service Account credentials is extremely long (exceeding the 63 char limit) and causing API calls to fail.

## Diagnostics

> Failure: Workflow.argoproj.io \"hello-world-hxtr5\" is invalid: metadata.labels: Invalid value: \"system-serviceaccount-sandbox-sandbox-mehdi-wf-deleteme-usw2-ppd-qal-automation\": must be no more than 63 characters"

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

Impacted by this bug? Give it a 👍. We prioritise the issues with the most 👍.

### Additional contract requirements

- When the generated creator label value exceeds 63 characters, truncate it to its last 63 characters.
