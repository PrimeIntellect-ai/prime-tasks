Consumer using multiple "filter_subjects" is not receiving all messages when combined with "by_start_time" deliver policy
### Observed behavior

**Summary and example of the problem:**

I have `test` stream which contains exactly three messages in following subjects:
- `events.subjectOne`
- `events.subjectTwo`
- `events.subjectThree`

I have two consumers created on this stream:
- first consumer uses `filter_subjects: ["events.*"]` pattern,
- second one uses explicit `filter_subjects: ["events.subjectOne","events.subjectTwo","events.subjectThree",]`

After creating consumers first of them has `num_pending` messages set to 3, which is correct value, but second one receives `num_pending` as 2, even though it should also receive all messages. This only happens when consumers have set `deliver_policy` to `by_start_time`.

Similar behavior could be observed using different subject combinations, but probably at least 2 different subjects are required with multiple messages. When only two messages exists both consumers have `num_pending` set to 2, which is correct.

**Detailed messages received using `nats sub ">"`**

```
Stream creation:

[#7] Received on "$JS.API.STREAM.CREATE.test" with reply "_INBOX.1W01W6HG0ZCF0JTK7PJ3XJ.1W01W6HG0ZCF0JTK7PJ45T"
{"name":"test","subjects":["events.>"],"max_msgs_per_subject":10000000,"max_msgs":10000000,"deny_purge":false,"discard":"old","max_age":604800000000000,"retention":"limits","num_replicas":1,"duplicate_window":300000000000}

[#9] Received on "_INBOX.1W01W6HG0ZCF0JTK7PJ3XJ.1W01W6HG0ZCF0JTK7PJ45T"
{"type":"io.nats.jetstream.api.v1.stream_create_response","config":{"name":"test","subjects":["events.\u003e"],"retention":"limits","max_consumers":-1,"max_msgs":10000000,"max_bytes":-1,"max_age":604800000000000,"max_msgs_per_subject":10000000,"max_msg_size":-1,"discard":"old","storage":"file","num_replicas":1,"duplicate_window":300000000000,"compression":"none","allow_direct":false,"mirror_direct":false,"sealed":false,"deny_delete":false,"deny_purge":false,"allow_rollup_hdrs":false,"consumer_limits":{}},"created":"2024-11-05T09:42:37.025040829Z","state":{"messages":0,"bytes":0,"first_seq":0,"first_ts":"0001-01-01T00:00:00Z","last_seq":0,"last_ts":"0001-01-01T00:00:00Z","consumer_count":0},"ts":"2024-11-05T09:42:37.025677661Z","did_create":true}


Messages in stream:

[#11] Received on "events.subjectOne"
test1

[#12] Received on "events.subjectTwo"
test2

[#13] Received on "events.subjectThree"
test3


First consumer:

[#14] Received on "$JS.API.CONSUMER.DURABLE.CREATE.test.wildcard-consumer" with reply "_INBOX.1W01W6HG0ZCF0JTK7PJ3XJ.1W01W6HG0ZCF0JTK7PJ49Y"
{"config":{"durable_name":"wildcard-consumer","filter_subjects":["events.*"],"deliver_policy":"by_start_time","opt_start_time":"2024-11-05T08:42:36.947Z"},"stream_name":"test","action":"create"}

[#16] Received on "_INBOX.1W01W6HG0ZCF0JTK7PJ3XJ.1W01W6HG0ZCF0JTK7PJ49Y"
{"type":"io.nats.jetstream.api.v1.consumer_create_response","stream_name":"test","name":"wildcard-consumer","created":"2024-11-05T09:42:37.028304635Z","config":{"durable_name":"wildcard-consumer","deliver_policy":"by_start_time","opt_start_time":"2024-11-05T08:42:36.947Z","ack_policy":"none","max_deliver":-1,"filter_subjects":["events.*"],"replay_policy":"instant","max_waiting":512,"num_replicas":0},"delivered":{"consumer_seq":0,"stream_seq":0},"ack_floor":{"consumer_seq":0,"stream_seq":0},"num_ack_pending":0,"num_redelivered":0,"num_waiting":0,"num_pending":3,"ts":"2024-11-05T09:42:37.028627946Z"}


Second consumer:

[#18] Received on "$JS.API.CONSUMER.DURABLE.CREATE.test.explicit-subjects-consumer" with reply "_INBOX.1W01W6HG0ZCF0JTK7PJ3XJ.1W01W6HG0ZCF0JTK7PJ4E3"
{"config":{"durable_name":"explicit-subjects-consumer","filter_subjects":["events.subjectOne","events.subjectTwo","events.subjectThree"],"deliver_policy":"by_start_time","opt_start_time":"2024-11-05T08:42:36.947Z"},"stream_name":"test","action":"create"}

[#20] Received on "_INBOX.1W01W6HG0ZCF0JTK7PJ3XJ.1W01W6HG0ZCF0JTK7PJ4E3"
{"type":"io.nats.jetstream.api.v1.consumer_create_response","stream_name":"test","name":"explicit-subjects-consumer","created":"2024-11-05T09:42:37.029950864Z","config":{"durable_name":"explicit-subjects-consumer","deliver_policy":"by_start_time","opt_start_time":"2024-11-05T08:42:36.947Z","ack_policy":"none","max_deliver":-1,"filter_subjects":["events.subjectOne","events.subjectTwo","events.subjectThree"],"replay_policy":"instant","max_waiting":512,"num_replicas":0},"delivered":{"consumer_seq":0,"stream_seq":1},"ack_floor":{"consumer_seq":0,"stream_seq":0},"num_ack_pending":0,"num_redelivered":0,"num_waiting":0,"num_pending":2,"ts":"2024-11-05T09:42:37.030212597Z"}
```


### Expected behavior

In example above second consumer should have `num_pending` set to 3, as its filter covers all existing messages. Due to wrong `num_pending` number second consumer is not receiving all messages.

### Server and client version

nats-server in Docker: nats:2.10.18-alpine3.20
nats-cli: 0.0.35
nats client Deno: nats@v1.28.2

### Host environment

Windows 10 Pro 22H2

### Steps to reproduce

See simple script written in Deno which is reproducing this behavior:
[nats-server-bug.zip](https://github.com/user-attachments/files/17630981/nats-server-bug.zip)

### Additional contract requirements

For a consumer with multiple subject filters and a by-start-time delivery policy, `num_pending` must include every stored message whose subject matches at least one filter and whose timestamp is at or after the requested start time. Every such message must also be available for delivery; reporting it as pending must not substitute for delivering it.
