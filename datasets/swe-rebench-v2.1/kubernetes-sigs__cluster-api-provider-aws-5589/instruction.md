Kubernetes API server rolling restarts experience client-side disruption
/kind bug

**What steps did you take and what happened:**
[A clear and concise description of what the bug is.]

An [automated test](https://github.com/openshift/origin/blob/6767b922e0d15c31c3fc349c659987ce1922d650/test/extended/apiserver/rollout.go#L36) that forces kube API server restarts observed that roughly 30 seconds after the kube api-server returns HTTP 500s from `/readyz` pre-shutdown, clients are getting `ECONNRESET` when trying to read responses.

**What did you expect to happen:**

Clients would not have their connections interrupted.

**Anything else you would like to add:**
[Miscellaneous information that will assist in solving the issue.]

The `target_health_state.unhealthy.draining_interval_seconds` attribute should probably be set to something higher than the default (which is 0) in order to make client interactions more resilient to kube-api-server restarts.

This draining interval is separate from the health check interval seconds we currently set - that one just tells AWS how often to invoke the health check.

See the [TargetGroupAttribute docs](https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_TargetGroupAttribute.html) for specifics.

This was observed during OpenShift testing, but is applicable generally to anyone restarting their KAS.

/area networking
/triage accepted
