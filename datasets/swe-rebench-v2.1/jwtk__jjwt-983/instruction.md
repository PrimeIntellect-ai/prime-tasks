JwkSet unexpectedly "secret" / Jackson cannot serialize JwkSet
<!--
PLEASE DO NOT USE GITHUB ISSUES TO ASK QUESTIONS!

The JJWT team uses GitHub Issues only to track actionable work that requires changes to the JJWT codebase.

If you have a usability or general question about JJWT, please instead post your question to StackOverflow using the following JJWT-specific link:

https://stackoverflow.com/questions/ask?tags=jjwt&guided=false

To help ensure you receive a timely response, please follow the StackOverflow guidelines on how to ask a good question: https://stackoverflow.com/help/how-to-ask

Ok, now that that's out of the way - if you're still sure you need to report a bug, please fill in the sections below...
-->

**Describe the bug**

The default (and only) JWK set builder considers all "keys" members as secret, even if the set contains only public keys.
In turn, this results in a failure to serialize the set using Jackson redacted data cannot be serialized.

**To Reproduce**

To repro
1. Add Jackson to the classpath
2. Create a JWK for a public key
3. Add that JWK to a JWKSet using the builder
4. Attempt to serialize that set using Jackson's ObjectMapper

A complete example follows.

```kotlin
dependencies {
    implementation("io.jsonwebtoken:jjwt-api:0.12.6")
    runtimeOnly("io.jsonwebtoken:jjwt-impl:0.12.6")
    runtimeOnly("io.jsonwebtoken:jjwt-jackson:0.12.6")
}
```

```java
static void jwkSetUnexpectedlyPrivate(RSAPublicKey pubKey) throws Exception {
    final ObjectMapper jacksonMapper = new ObjectMapper();

    final RsaPublicJwk pubJwk = Jwks.builder()
            .key(pubKey)
            .build();

    // PASS; unredacted human-readable form
    pubJwk.toString();

    // PASS; unredacted
    jacksonMapper.writeValueAsString(pubJwk);

    // When in set, now redacted
    final JwkSet jwkSet = Jwks.set()
            .add(pubJwk)
            .build();

    // FAIL? Redacted; Possibly a safe default, not terribly problematic for debug statements
    jwkSet.toString();

    // FAIL; Throws an exception. Prevents exposure of the set for external consumption of public keys.
    jacksonMapper.writeValueAsString(jwkSet);
    // com.fasterxml.jackson.databind.exc.InvalidDefinitionException: No serializer found for class
    // io.jsonwebtoken.impl.lang.RedactedSupplier and no properties discovered to create BeanSerializer
    // (to avoid exception, disable SerializationFeature.FAIL_ON_EMPTY_BEANS)
    // (through reference chain: io.jsonwebtoken.impl.security.DefaultJwkSet["keys"])
}
```

**Expected behavior**

1. It is expected that sets are either conditionally redacted based on whether their content is redacted,
OR this behavior can be configured in some way to allow proper serialization.
2. It should be possible to serialize a JwkSet using Jackson

**Screenshots**

See code sample above.

### Additional contract requirements

- A JWK set whose members are all public JWKs must be serializable with Jackson without any extra configuration. The serialized `keys` array must contain each key's public members (for an RSA key, `kty`, `n`, and `e`).
- A JWK set that contains a secret JWK must not expose that key's secret material when serialized with Jackson. Refusing to serialize such a set is acceptable.
