Redwood does not work anymore with the operator in 7.3.x after it is was classified stable
### What happened?

Redwood was renamed from `ssd-redwood-1-experimental` to `ssd-redwood-1`.

- Since the new value is not in the spec, i'm not able to enable it.
- If I set it to `ssd-redwood-1-experimental`, the cluster will change its state, but the operator will forever error loop, since FoundationDB will report back that it is using `ssd-redwood-1` instead of `ssd-redwood-1-experimental` that the operator expects.

### What did you expect to happen?

`ssd-redwood-1` should be allowed in the spec as a valid value

### How can we reproduce it (as minimally and precisely as possible)?

use 7.3.x, change storage-engine to `ssd-redwood-1-experimental`

### Anything else we need to know?

_No response_

### FDB Kubernetes operator

1.26.0

### Kubernetes version

<details>

```console
Client Version: v1.28.2
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
Server Version: v1.28.1
```

</details>


### Cloud provider

<details>
microk8s
</details>

### Additional contract requirements

- The stable storage-engine value `ssd-redwood-1` must be accepted by the cluster API schema.
- When FoundationDB 7.3.x reports the stable engine name `ssd-redwood-1` for a cluster configured with that engine, the operator must accept the configuration instead of repeatedly erroring during reconciliation.
