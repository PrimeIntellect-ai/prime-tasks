Feature: add sasl_oauthbearer support
Hi!

Faststream doesn't allow to authenticate with Oauth. According to [librdkafka/CONFIGURATION.md](https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md) `sasl.mechanism` must be set to `OAUTHBEARER`. However this value will get overwritten when specifying it in config and providing it during broker creation. To be precise it will get overwritten by one of `_parse_*` functions in `faststream\confluent\security.py` depending on which security class from `faststream\security.py` will be chosen. Changes should allow broker configuration with oauth:

```
broker = KafkaBroker(
    "host:port",
    config=config,
    security=SASLOAuthBearer(use_ssl=True),
)
```

To achieve this we need to implement a new security class and new parser. I have already created fork with these changes and successfully deployed it.

### Additional contract requirements

- The AsyncAPI security scheme for `SASLOAuthBearer` must use the `oauthbearer` key with the value `{"type": "oauth2", "$ref": ""}`.
- Configuring a broker with `SASLOAuthBearer(use_ssl=True)` must produce a connection configuration with `sasl.mechanism` set to `OAUTHBEARER` and `security_protocol` set to `SASL_SSL`.
