[Bug] Infinity loop in Consume() method
##### Versions

| Sarama | Kafka | Go |
|--------|-------|----|
| v1.34.1 | - | 1.18 |

##### Configuration

What configuration values are you using for Sarama and Kafka?
``` go
        // default reader configuration
        readerOptions := make([]kafka.ReaderOption, 0)
        readerOptions = append(readerOptions, kafka.WithReaderTlSConfig(nil))
	readerOptions = append(readerOptions, kafka.WithReaderSaslConfig(user, password, kafka.SaslAlgorithm("SHA512")))

	reader, err := kafka.NewReader(brokers, consumerGroup, readerOptions...)
```

##### Logs

<details><summary>logs: CLICK ME</summary>
<p>

```
[Sarama] 2023/01/25 15:27:40 client/coordinator retrying after 250ms... (3 attempts remaining)
[Sarama] 2023/01/25 15:27:40 client/coordinator requesting coordinator for consumergroup kafka-demo from <ip>
[Sarama] 2023/01/25 15:27:40 client was not authorized to access group kafka-demo while attempting to find coordinator
[Sarama] 2023/01/25 15:27:40 client/coordinator retrying after 250ms... (2 attempts remaining)
[Sarama] 2023/01/25 15:27:40 client/coordinator requesting coordinator for consumergroup kafka-demo from <ip>
[Sarama] 2023/01/25 15:27:41 client was not authorized to access group kafka-demo while attempting to find coordinator
[Sarama] 2023/01/25 15:27:41 client/coordinator retrying after 250ms... (1 attempts remaining)
[Sarama] 2023/01/25 15:27:41 client/coordinator requesting coordinator for consumergroup kafka-demo from <ip>
[Sarama] 2023/01/25 15:27:41 client was not authorized to access group kafka-demo while attempting to find coordinator
[Sarama] 2023/01/25 15:27:43 client/coordinator requesting coordinator for consumergroup kafka-demo from <ip>
[Sarama] 2023/01/25 15:27:43 client was not authorized to access group kafka-demo while attempting to find coordinator
[Sarama] 2023/01/25 15:27:43 client/coordinator retrying after 250ms... (3 attempts remaining)

...infinity loop...
```

</p>
</details>

##### Problem Description
If the client is not authorized to access the consumer group, the Consume() method is expected to return an error, but this does not happen. Instead, the Consume() method freezes.

[HIDDEN]

### Additional contract requirements

- When failures exhaust the configured retry limit, `Consume()` must terminate and return an error rather than retry indefinitely.
