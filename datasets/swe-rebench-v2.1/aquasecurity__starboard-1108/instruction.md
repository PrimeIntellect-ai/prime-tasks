Limit the num of failure entries per control check in cluster compliance detail report
***The problem:***
Limiting the number of failure entries per control check on the cluster compliance detail report is required.
Especially in mid/big clusters when there are many resources with failures will produce a huge cluster compliance detail report that exceeds the etcd limits.

***Suggested resolution:***
it is suggested to limit, by configuration, the number of failures entries per control check in the cluster compliance detail report

Fixed by: #1108

### Additional contract requirements

- The number of failure entries kept for each control check in the cluster compliance detail report is limited by the `compliance.failEntriesLimit` setting of the Starboard configuration data, whose value is a decimal integer.
- When the limit truncates a control check's failure entries, retain the earliest entries in their existing order.
- The cluster compliance report manager is constructed as `NewMgr(client, log, config)`, where `config` is the `starboard.ConfigData` that holds the setting.
