Better handling for periods in pipeline name
# Summary

This passes validation in the controller:
```yaml
apiVersion: numaflow.numaproj.io/v1alpha1
kind: Pipeline
metadata:
  name: inf-udf-v0.2
...
```
But then errors trying to create the service for daemon:
```json
{
  "level": "error",
  "ts": 1668268595.0106926,
  "logger": "numaflow.controller-manager",
  "caller": "pipeline/controller.go:82",
  "msg": "Reconcile error",
  "namespace": "default",
  "pipeline": "inf-udf-v0.2",
  "error": "failed to create daemon service, Service \"inf-udf-v0.2-daemon-svc\" is invalid: metadata.name: Invalid value: \"inf-udf-v0.2-daemon-svc\": a DNS-1035 label must consist of lower case alphanumeric characters or '-', start with an alphabetic character, and end with an alphanumeric character (e.g. 'my-name',  or 'abc-123', regex used for validation is '[a-z]([-a-z0-9]*[a-z0-9])?')",
  "stacktrace": "..."
}
```

Would be good to not pass Pipeline validation if periods aren't allowed, or allow them and adjust service name to compensate.

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

If you wish to see this enhancement implemented please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.
