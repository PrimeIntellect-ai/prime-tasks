Should not allow to create repair/backup tasks with same name
**Describe the bug**
Currently we allow to have multiple tasks with same name, which should not be the case:

```
    repairs:
    - interval: "0"
      name: test-name
      numRetries: 3
      smallTableThreshold: 1GiB
      startDate: now
    - interval: "0"
      name: test-name
      numRetries: 3
      smallTableThreshold: 1GiB
      startDate: now
```

### Additional contract requirements

A ScyllaCluster must not contain two repair or backup task entries with the same name. This applies to duplicates within the repair list, within the backup list, and across the two lists.
