Unmarshalling error logs contain Slack user data
**Describe the bug**
When the dependency (`nlopes/slack`) can't marshall a message event, an error is logged.
The log contains information about the event, which contains much too much information on the Slack user.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to Slack
2. Click on the huddle icon; do it in a really public channel just to annoy lots of other people with your test.  Some of them might join to say hi!  Please tell them I said: "hello".
3. Dump the error logs of your botKube pod (`k logs botkube-blah`)
4. See error
```
Slack unmarshalling error: RTM Error: Received unmapped event "user_huddle_changed": {all my info about me}
```

**Expected behavior**
Don't log things that don't matter.

**Screenshots**
n/a

**Additional context**
`nlopes/slack` has moved to `slack-go/slack`, and you should probably also update your dependency, but the problem with using this tool is that it listens to every possible slack event.
(ref: https://github.com/slack-go/slack/blob/0e14c9d4a15c91e845bc371fe91ee58763a3813a/websocket_managed_conn.go#L494)
Which means BotKube listens to every event
Which makes this tool a really frightening kind of slack spy program that's running in my kubernetes cluster and outputting employee information in error logs.
