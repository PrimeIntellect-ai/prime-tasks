CRD Strategy: "Replace" ConcurrencyPolicy
We should add a new option to CRD Strategy concurrencyPolicy called "Repalce", which will delete the custom resource and replace it with a new one when there is a new launch config.

In the case of RollingUpgrade this really helps with modifications that happen during the upgrade, for example if the spot price changes, you don't have to wait for the upgrade to complete, you can just stop the upgrade by deleting the custom resource and submit a new one.

### Additional contract requirements

- The accepted `concurrencyPolicy` value for this option is the lowercase string `replace`, consistent with the existing `forbid` and `allow` values.
- When a new launch configuration arrives under `replace`, the active custom resource for the previous launch configuration is deleted and a replacement is submitted without waiting for that resource to finish.
- A spot-price change during a rolling upgrade can be discovered and applied before the nodes are ready; it does not have to wait for the upgrade to complete.
