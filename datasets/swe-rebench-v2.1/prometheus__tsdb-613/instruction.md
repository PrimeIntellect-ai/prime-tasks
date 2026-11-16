prometheus_tsdb_compactions_failed_total metric not incremented when compaction fails
We have had a corrupted WAL after a disk issue and got the following error messages in the logs
```
May 20 01:01:59 q2-gog-sh00-pm0 prometheus[3157]: level=error ts=2019-05-20T01:01:59.300Z caller=db.go:363 component=tsdb msg="compaction failed" err="reload blocks: head truncate failed: create checkpoint: read segments: corruption in segment /datadrive/prometheus/db/platform/wal/00225282 at 32768: unexpected first record, dropping buffer"
```

however, the value of `prometheus_tsdb_compactions_failed_total` isn't increasing when this happens.
