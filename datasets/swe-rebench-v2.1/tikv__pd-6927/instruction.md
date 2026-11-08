No update logs when set balance-hot-region-scheduler attributes
## Bug Report

<!-- Please answer these questions before submitting your issue. Thanks! -->

### What did you do?
/var/lib/pd/log # grep 'config is updated' * |awk -F" " '{print $1,$2,$3,$4,$5,$6,$7,$8,$9}'
[2022/01/20 10:01:37.910 +00:00] [INFO] [server.go:957] ["PD server config is
[2022/01/20 11:10:56.768 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/20 11:12:36.790 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/20 11:14:16.774 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/20 11:15:56.775 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/20 11:17:36.783 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/20 11:19:16.775 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/20 11:20:56.783 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/20 11:21:25.572 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/21 05:44:51.526 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/21 05:46:31.542 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/21 05:48:11.541 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/21 05:49:51.532 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/21 05:51:31.540 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/21 05:53:11.541 +00:00] [INFO] [server.go:835] ["schedule config is updated"]
[2022/01/21 05:54:05.620 +00:00] [INFO] [server.go:835] ["schedule config is updated"]

2022-01-21T13:59:06.490+0800    INFO    pd-basic/pdbasic_schedule_test.go:299   /pd-ctl scheduler config balance-hot-region-scheduler set strict-picking-store false:Success!
2022-01-21T13:59:06.490+0800    INFO    oltppkg/util.go:62      workload run    {"wait": "5m0s"}
<!-- If possible, provide a recipe for reproducing the error. -->

### What did you expect to see?
See update logs when set balance-hot-region-scheduler parameters.

### What did you see instead?
No related logs print.

### What version of PD are you using (`pd-server -V`)?
/ # /pd-server -V
Release Version: v5.4.0-nightly
Edition: Community
Git Commit Hash: 964569d45ac0685110d12665e6ade8680042c8e5
Git Branch: heads/refs/tags/v5.4.0-nightly
UTC Build Time:  2022-01-20 06:11:07

Minio logs can be get from tcms via plan id: 600774, testbed: pd-schedule-hongm-tps-600774-1-763

### Additional contract requirements

When the balance-hot-region-scheduler configuration is changed through the
scheduler-config endpoint (i.e. the request that returns "Config is updated."),
the server must emit an INFO log message whose text is exactly
`hot-region-scheduler config is updated`.
