Sidecar containers cannot specify probes
### Description of the feature or enhancement:
Sidecar containers, unlike init containers, [support probes](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/#differences-from-init-containers). `addInitContainer` doesn't support this and will throw an error if `liveness`, `readiness`, or `startup` are specified:
https://github.com/cdk8s-team/cdk8s-plus/blob/f7c11148f65084b35fb5d3273a31af387015bc8f/src/pod.ts#L124-L135

I'd like to be able to specify these probes for sidecar containers.

### Use Case:
Since a sidecar container does not exit before the main container starts, probes are the only means available for delaying the startup of the main container beyond the simplest possible cases. Sidecar containers may require some time to be ready after starting, and in my case it's important that the sidecar container be _ready_, not just _started_, by the time the main container starts.

### Proposed Solution:

It seems relatively straightforward to build on #3812 and [HIDDEN]

### Other:

* [x] :wave: I may be able to implement this feature request
* [ ] :warning: This feature might incur a breaking change

---

This is a :rocket: Feature Request

### Additional contract requirements

- An init container used as a sidecar, with `restartPolicy` specified, may specify `liveness`, `readiness`, and `startup` probes. Any configured probes must be present on that container in the resulting Pod.
