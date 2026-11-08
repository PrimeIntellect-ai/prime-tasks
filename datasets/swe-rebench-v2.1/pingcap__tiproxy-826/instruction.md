Connection jitters when the connection load difference is too much
## Bug Report

Please answer these questions before submitting your issue. Thanks!

### 1. Minimal reproduce step (Required)

<!-- a step by step guide for reproducing the bug. -->

Create a workload that contains one big query and many normal queries

### 2. What did you expect to see? (Required)

TiDB load is balanced and has no jitter

### 3. What did you see instead (Required)

Connections are migrated back and forth

### 4. What is your version? (Required)

<!-- Paste the output of tiproxy version -->
<!-- Paste the output of tiproxyctl version if related -->
<!-- Paste the output of SELECT tidb_version()  if related -->

master
