Bug: Changing defaultPendingTimeoutSeconds should not affect already created jobs
When updating the `defaultPendingTimeoutSeconds`, any already ongoing jobs will be affected by the change. This is probably undesirable, especially if the cluster administrator shortens the timeout from a longer one to a shorter one, it may cause previously created jobs to be killed. We should uphold a principle such that old resources should NOT be affected by newly updated defaults.

[HIDDEN]

### Additional contract requirements

- An explicitly specified pending timeout must be preserved; the configured default applies only when the job does not specify a timeout.
- When a job omits a pending timeout, its effective timeout must be determined by the configured default at creation and must not change if that default is updated later.
