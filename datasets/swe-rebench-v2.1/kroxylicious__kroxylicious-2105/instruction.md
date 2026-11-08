Kafka 4.0.0 : Oauthbearer fail without change properties
**Describe the bug**
Kafka 4.0.0 introduces a new "mandatory" system property when using `SASL_SSL` with `OAUTHBEARER`.
The property is described here : https://kafka.apache.org/documentation/#systemproperties_org.apache.kafka.sasl.oauthbearer.allowed.urls
Because of that, the proxy fails to start when upgrading from `0.11.0` to `0.12.0`

**To Reproduce**
```yaml
filterDefinitions:
  - name: jwt
    type: OauthBearerValidation
    config:
      jwksEndpointUrl: https://my.jwks.url
defaultFilters:
- jwt
```

**Expected behavior**
As a proxy owner, I want to upgrade from `0.11` to `0.12` without disruption.

**YAML files and logs**

```
io.kroxylicious.proxy.plugin.PluginConfigurationException: Exception initializing filter factory jwt with config Config[jwksEndpointUrl=https://my.jwks.url, jwksEndpointRefreshMs=null, jwksEndpointRetryBackoffMs=null, jwksEndpointRetryBackoffMaxMs=null, scopeClaimName=null, subClaimName=null, authenticateBackOffMaxMs=null, authenticateCacheMaxSize=null, expectedAudience=null, expectedIssuer=null]: https://my.jwks.url is not allowed. Update system property 'org.apache.kafka.sasl.oauthbearer.allowed.urls' to allow https://my.jwks.url
	at io.kroxylicious.proxy.bootstrap.FilterChainFactory$Wrapper.<init>(FilterChainFactory.java:55)
	at io.kroxylicious.proxy.bootstrap.FilterChainFactory.<init>(FilterChainFactory.java:114)
	at io.kroxylicious.proxy.KafkaProxy.startup(KafkaProxy.java:138)
	at io.kroxylicious.app.Kroxylicious.call(Kroxylicious.java:73)
	at io.kroxylicious.app.Kroxylicious.call(Kroxylicious.java:35)
	at picocli.CommandLine.executeUserObject(CommandLine.java:2031)
	at picocli.CommandLine.access$1500(CommandLine.java:148)
	at picocli.CommandLine$RunLast.executeUserObjectOfLastSubcommandWithSameParent(CommandLine.java:2469)
	at picocli.CommandLine$RunLast.handle(CommandLine.java:2461)
	at picocli.CommandLine$RunLast.handle(CommandLine.java:2423)
	at picocli.CommandLine$AbstractParseResultHandler.execute(CommandLine.java:2277)
	at picocli.CommandLine$RunLast.execute(CommandLine.java:2425)
	at picocli.CommandLine.execute(CommandLine.java:2174)
	at io.kroxylicious.app.Kroxylicious.main(Kroxylicious.java:123)
```

**Additional context**

- A test is missing to assert the `configure` step of `OAuthBearerValidatorCallbackHandler` in `OauthBearerValidation`
- [HIDDEN]
```java
[HIDDEN]
[HIDDEN]
[HIDDEN]
```

### Additional contract requirements

- When OAuthBearerValidation is initialized, its configured JWKS endpoint must be authorized by Kafka's `org.apache.kafka.sasl.oauthbearer.allowed.urls` property, without requiring the operator to add that endpoint to the property manually.
