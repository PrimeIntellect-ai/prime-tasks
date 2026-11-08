Bug: confluent.KafkaRouter with SASLScram512 fails in version 0.5.36
**Describe the bug**
From https://discord.com/channels/1085457301214855171/1085457302280228898/1352183480049729566:

After updating to version faststream==0.5.36, we’re experiencing an issue with confluent.fastapi.KafkaRouter on startup. Our dependencies: faststream==0.5.36, confluent-kafka==2.8.0.

We rolled back to version 0.5.35, and the issue disappeared.

**How to reproduce**
Include source code:

```python
security = SASLScram512(
    username=KAFKA_SETTINGS.kafka_auth_user,
    password=KAFKA_SETTINGS.kafka_auth_password,
    use_ssl=False,
)
router = KafkaRouter(
    KAFKA_SETTINGS.kafka_instance,
    security=security,
)
```

**Observed behavior**
```txt
File "/usr/local/lib/python3.8/site-packages/faststream/broker/fastapi/router.py", line 324, in start_broker_lifespan
    await self.broker.start()
File "/usr/local/lib/python3.8/site-packages/faststream/confluent/broker/broker.py", line 456, in start
    await super().start()
File "/usr/local/lib/python3.8/site-packages/faststream/broker/core/usecase.py", line 219, in start
    await self.connect()
File "/usr/local/lib/python3.8/site-packages/faststream/confluent/broker/broker.py", line 423, in connect
    return await super().connect(**kwargs)
File "/usr/local/lib/python3.8/site-packages/faststream/broker/core/usecase.py", line 226, in connect
    self._connection = await self._connect(**connection_kwargs)
File "/usr/local/lib/python3.8/site-packages/faststream/confluent/broker/broker.py", line 435, in _connect
    native_producer = AsyncConfluentProducer(
File "/usr/local/lib/python3.8/site-packages/faststream/confluent/client.py", line 109, in __init__
    self.producer = Producer(final_config, logger=self.logger) # type: ignore[call-arg]
cimpl.KafkaException: KafkaError{code=_INVALID_ARG,val=-186,str="No such configuration property: "sasl_mechanism""}
```

**Environment**
Our dependencies: faststream==0.5.36, confluent-kafka==2.8.0.

### Additional contract requirements

- The SASL settings must be handed to confluent-kafka under the configuration property names it accepts: the mechanism as `sasl.mechanism`, the username as `sasl.username`, and the password as `sasl.password`. The invalid names `sasl_mechanism`, `sasl_plain_username` and `sasl_plain_password` must not reach confluent-kafka.
