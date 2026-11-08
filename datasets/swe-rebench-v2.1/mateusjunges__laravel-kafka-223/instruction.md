Kafka transaction when having multiple pushs
Hii there,
First of all, i appreciate your contribution for the laravel community !! i wanted to know if there's a way or a mechanism to make a transaction when publishing multiple topics after saving in the database,

`Kafka::publishOn('topic1')->withMessage($message)->send();
            Kafka::publishOn('topic2')->withMessage($message)->send();`

i want to wrap it with something like kafka::transaction, when there's for example a problem in topic2 for some reason (like a time out or any other expection) it will remove the message published in topic2 or to send another message automatically to cancel it.

Any advice ?
Thank you in advance.

### Additional contract requirements

Publishing must go through a producer builder whose topic is set explicitly:

- `Junges\Kafka\Kafka::publish(?string $broker = null): MessageProducer` creates a producer builder, using the configured default broker when no broker is given.
- The producer builder exposes `onTopic(string $topic): self`, which sets the topic of the message being built and returns the builder for chaining.
- The producer builder exposes `build()`, which returns the producer object.

The testing fake mirrors this API:

- `Junges\Kafka\Support\Testing\Fakes\KafkaFake::publish(?string $broker = null): ProducerBuilderFake` creates a fake producer builder.
- `Junges\Kafka\Support\Testing\Fakes\ProducerBuilderFake::onTopic(string $topic): self` sets the topic of the message being built and returns the builder for chaining.

Messages and batches carry their own topic:

- `Junges\Kafka\Message\Message::onTopic(string $topic): self` sets the message topic and returns the message.
- `Junges\Kafka\Producers\MessageBatch::onTopic(string $topicName): self` sets the topic for the whole batch and returns the batch.

The producer exposes `produce(ProducerMessage $message): bool` and `produceBatch(MessageBatch $messageBatch): int`.

Transactional publishing:

- The producer exposes `beginTransaction(int $timeoutInMilliseconds = 1000): void`, `commitTransaction(int $timeoutInMilliseconds = 1000): void` and `abortTransaction(int $timeoutInMilliseconds = 1000): void`, which start, commit and abort a Kafka transaction respectively.

Publishing to multiple topics may be grouped in one Kafka transaction. If a later publish fails, aborting that transaction must prevent earlier messages in that transaction from being committed.
