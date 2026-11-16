Harmonize list headers for "trigger list", "cronjob list" and "apiserver list"
Actually the columns wrt to Sink / Subscription are different:

* CronJon and Apiserver source display the sink shortcut ('svc:myservice')
* Trigger shows the resolved URL ("SUBSCRIBER_URL")

Also, the condition and reason columns should be the same as for services.
Should we add AGE, too ?

### Additional contract requirements

- The `trigger list`, `cronjob list` and `apiserver list` outputs display a `SINK` column. The `trigger list` output shows the sink shortcut (for example `svc:myservice`) in that column, consistent with the source lists, instead of a subscriber-URI column.
- The `trigger list`, `cronjob list`, `apiserver list` and `binding list` outputs each include an `AGE` column.
- The `trigger list`, `cronjob list` and `apiserver list` outputs include `CONDITIONS`, `READY` and `REASON` columns, matching the service list.
