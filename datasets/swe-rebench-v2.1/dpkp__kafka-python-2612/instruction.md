KeyError in kafka/consumer/fetcher.py _reset_offsets_async()
After upgrade from 2.1.5 to 2.2.3 we sporadically ran into:

```
KeyError
TopicPartition(topic='redacted-topic-name', partition=117)
```
on line 428 here: https://github.com/dpkp/kafka-python/blame/2767d14b6cd33f2e55e7004e2e33467746a8fd9e/kafka/consumer/fetcher.py#L428

Worse, the effect of this exception is that the offset for that partition got reverted to "earliest" and thus caused the consumer to re-consume data again.

From what I can tell, this code was recently introduced in https://github.com/dpkp/kafka-python/pull/2593
