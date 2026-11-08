Jetstream Isbsvc Replicas
# Summary

What change needs making?

I've noticed in the documentation and in the source code that if the number of replicas of the jetsream isbsvc is <3, it will still create 3 pods and replicas.  I would like like to have a single isbsvc pod with no extra replicas.  Are there any fundamental limitations that would prevent this?

# Use Cases

When would you use this?

I am running on an embedded device and trying to cut down on overhead as much as possible.  The device is frequently powered on and off as well.  On startup, we sometimes have issues with the isbsvc pods struggling to communicate with each other (e.g. establish a raft leader - Some of these issues have been addressed in recent jetstream releases, but we still have issues sometimes).  I think that life would be a lot easier if we just had a single pod for the buffer rather than 3.  Since we are running on an embedded device, I don't see any advantage to having 3 replicas and we are paying extra costs for it.

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

If you wish to see this enhancement implemented please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.

### Additional contract requirements

- `JetStreamBufferService` in package `pkg/apis/numaflow/v1alpha1` exposes a public method `GetReplicas() int` that returns the effective replica count for the JetStream buffer: `3` when the replica count is unset or explicitly set to `2`, `1` when explicitly set to `1`, and otherwise the configured value.
- The StatefulSet spec produced for the JetStream buffer service (`GetStatefulSetSpec`) uses that effective replica count, so an explicit replica count of `1` produces a workload with a single replica.
- With `stream.replicas` configured as `1`, a JetStream buffer and its side-input store must be creatable on a single-member JetStream server, and the created stream must use one replica.
