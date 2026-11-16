Upgrade keeps replacing resource
Looks like we messed up the iteration back in #179 where we did:
```
[HIDDEN]
```

There are also other issues leading to activeResource detection having the wrong resources in the list when many instance groups are upgrading simultaneously - the end result of this is that we keep deleting the upgrade resource and replacing it with a new one.

In addition, there is a problem when we go to upgrade straight after updating the ASG with a new launch config - since the cache still has a reference to old ASG with old launch config - this causes recreation of the upgrade resource after the initial submission. - we should requeue right after / if we make an update to the scaling group.

### Additional contract requirements

- Upgrade-resource discovery must select resources associated with the scaling group being reconciled and distinguish active from completed resources; reconciling one group must not delete or replace another group's resource.
- If an update changes the scaling group, end the current reconciliation path and requeue so subsequent work does not use stale cached scaling-group data.
- After an update to the scaling group, the reconciliation state must be `v1alpha1.ReconcileModifying`.
