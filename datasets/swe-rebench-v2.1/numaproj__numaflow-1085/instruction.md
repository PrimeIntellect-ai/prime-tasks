Resuming a paused pipeline sets incorrect replicas for some type of vertices
**Describe the bug**

If a pipeline with an HTTP source is paused, when resuming it, it only brings the HTTP source replica back to 1, even if its `spec.scale.min` is set to a number > 1.

When we resume a pipeline, we always set the replica number to 1, and let the autoscaling kick in to bring the number back to normal, but it does not work for sources like HTTP, because they do not support autoscaling.

---

<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->

**Message from the maintainers**:

Impacted by this bug? Give it a 👍. We often sort issues this way to know what to prioritize.
