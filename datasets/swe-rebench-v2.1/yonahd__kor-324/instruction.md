Filter flags are not working --older-than , --newer-than
**Describe the bug**
The filter options doesn't seem to work, no matter what pass using one of these 2 , I always get the same (all) resources `--older-than , --newer-than`

**To Reproduce**

```
./kor.exe replicaset --include-namespaces testing --show-reason --older-than=1000h
```

**Expected behavior**
show only the older replicasets

**OS version, architecture and kor version**
Windows

### Additional contract requirements

For ReplicaSets, `--newer-than` must include only ReplicaSets younger than the specified duration.
