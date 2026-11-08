ServiceAccountName incorrectly configured in case vertex template exist
**Describe the bug**

In case the vertex template is configured, the `serviceAccountName` isn't respected and is set to `default`.


**To Reproduce**

A sample pipeline - in this case the `cat` vertice should be configured with serviceAccountName as `test-two` instead of `default`.

```yaml
apiVersion: numaflow.numaproj.io/v1alpha1
kind: Pipeline
metadata:
  name: simple-pipeline
spec:
  templates:
    vertex:
      metadata:
        annotations:
          cluster-autoscaler.kubernetes.io/safe-to-evict: "true"
      tolerations:
        - key: "kubernetes.azure.com/scalesetpriority"
          operator: "Equal"
          value: "spot"
          effect: "NoSchedule"
  vertices:
    - name: in
      source:
        # A self data generating source
        generator:
          rpu: 5
          duration: 1s
    - name: cat
      serviceAccountName: "test-two"
      udf:
        builtin:
          name: cat # A built-in UDF which simply cats the message
    - name: out
      sink:
        # A simple log printing sink
        log: {}
  edges:
    - from: in
      to: cat
    - from: cat
      to: out
```

**Expected behavior**
The serviceAccountName at the vertice level should be adhered

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Environment (please complete the following information):**

- Kubernetes: v1.29.2
- Numaflow: v1.1.5

**Additional context**
Add any other context about the problem here.

---

>For quick help and support, join our [slack](https://numaproj.slack.com/join/shared_invite/zt-19svuv47m-YKHhsQ~~KK9mBv1E7pNzfg#/shared-invite/email) channel.

<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->

**Message from the maintainers**:

Impacted by this bug? Give it a 👍. We often sort issues this way to know what to prioritize.
