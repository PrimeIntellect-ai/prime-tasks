Since v0.8.1 Slack fails with "failed to send msg with Slack: slack server error: 404 Not Found"
**Describe the bug**
After upgrading from 0.8.0 to 0.8.1, Slack messages are no long sent.
The configmap didn't change.

Downgrading to 0.8.0 solves the problem.

**To Reproduce**

Deploy kwatch 0.8.1 with this config map:

```
data:
  config.yaml: |
    maxRecentLogLines: 50
    ignoreFailedGracefulShutdown: true
    app:
      clusterName: xyz
    alert:
      slack:
        webhook: https://hooks.slack.com/services/XXXXXX/ZZZZZ
```

**Expected behavior**
Message sent to Slack:
```
time="2023-03-08T15:45:12Z" level=info msg=":tada: kwatch@v0.8.0 just started!"
time="2023-03-08T15:45:12Z" level=info msg="initializing slack with webhook url: https://hooks.slack.com/services/XXXXXX/ZZZZZ"
time="2023-03-08T15:45:12Z" level=info msg="sending message: :tada: kwatch@v0.8.0 just started!"
```

**Actual behavior**
No message sent to Slack and errors in logs:
```
time="2023-03-08T14:41:20Z" level=info msg=":tada: kwatch@v0.8.1 just started!"
time="2023-03-08T14:41:20Z" level=info msg="initializing slack with webhook url: https://hooks.slack.com/services/XXXXXX/ZZZZZ"
time="2023-03-08T14:41:20Z" level=info msg="sending message: :tada: kwatch@v0.8.1 just started!"
time="2023-03-08T14:41:21Z" level=error msg="failed to send msg with Slack: slack server error: 404 Not Found"
```

**Version/Commit**
0.8.1
