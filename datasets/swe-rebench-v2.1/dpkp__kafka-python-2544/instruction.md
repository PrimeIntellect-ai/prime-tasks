KafkaConsumer.position can block forever when single broker is unreachable
I have a situation where I am attempting to get the offset of the next record for each partition in a topic. When one of my brokers are down/unreachable via network, then it blocks. I can't figure out which of these timeout options I can tune to break out of this.

```
consumer = KafkaConsumer(bootstrap_servers=config.brokers, api_version=(0,10,1), reconnect_backoff_max_ms=100, fetch_max_wait_ms=config.session_timeout_ms, session_timeout_ms=config.session_timeout_ms, \
                        request_timeout_ms=config.request_timeout_ms, consumer_timeout_ms=2000, auto_offset_reset='latest')
        ps = [TopicPartition(config.topic, p) for p in consumer.partitions_for_topic(config.topic)]
        print("Assigning...")
        consumer.assign(ps)
        for p in ps:
            print(p)
            pos = consumer.position(p)
```

This will block at `pos = consumer.position(p)` once it attempts to retrieve the position from a partition belonging to the unreachable broker.

```
  File "/usr/lib64/nagios/plugins/kafka/consumer/fetcher.py", line 194, in update_fetch_positions
    self._reset_offset(tp)
  File "/usr/lib64/nagios/plugins/kafka/consumer/fetcher.py", line 245, in _reset_offset
    offsets = self._retrieve_offsets({partition: timestamp})
  File "/usr/lib64/nagios/plugins/kafka/consumer/fetcher.py", line 295, in _retrieve_offsets
    time.sleep(self.config['retry_backoff_ms'] / 1000.0)
```

### Additional contract requirements

- A caller can pass `timeout_ms` to `KafkaConsumer.position(partition, timeout_ms=None)` to bound initialization of an unknown position. If no position can be obtained before the bound expires, the call completes with `None` rather than waiting indefinitely.

- `Fetcher._reset_offset(partition, timeout_ms=None)` in module `kafka.consumer.fetcher` accepts an optional `timeout_ms` argument. When a timeout is supplied it bounds the offset lookup for that partition, and if the timeout expires while fetching offsets a `KafkaTimeoutError` is raised.
