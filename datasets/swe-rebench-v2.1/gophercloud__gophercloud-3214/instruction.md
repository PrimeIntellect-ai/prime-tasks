[manila] add scheduler_hints field to manila shares
<!--
Before starting a PR, please read our [contributor tutorial](https://github.com/gophercloud/gophercloud/tree/master/docs/contributor-tutorial).
-->

https://docs.openstack.org/api-ref/shared-file-system/#create-share

Scheduler hints allow to create shares with affinity and anti-affinity rules, e.g.:

```json
{
    "share": {
...
        "scheduler_hints": {
            "same_host": "d9c66489-cf02-4156-b0f2-527f3211b243,4ffee55f-ba98-42d2-a8ce-e7cecb169182",
            "different_host": "903685eb-f242-4105-903d-4bef2db94be4"
        }
    }
}
```

### Additional contract requirements

- In package `github.com/gophercloud/gophercloud/v2/openstack/sharedfilesystems/v2/shares`, `CreateOpts` has an optional field `SchedulerHints *SchedulerHints` that is serialized as `scheduler_hints` in the create-share request body.
- `SchedulerHints` is a struct in the same package with the string fields `SameHost` (serialized as `same_host`), `DifferentHost` (serialized as `different_host`), and `OnlyHost` (serialized as `only_host`).
- `OnlyHost` is an admin-only hint available from API version 2.67.
