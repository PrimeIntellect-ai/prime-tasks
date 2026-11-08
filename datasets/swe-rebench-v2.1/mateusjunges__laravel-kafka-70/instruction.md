[BUG] Missing SASL Config Due to String Casing
**Describe the bug**
I was trying to debug why my SASL configs were not being loaded.   Everything looked correct, except the `usingSasl()` function below was still returning false.  This was because it checks [HIDDEN], whereas our config was in  lowercase.

[HIDDEN]

Because Kafka itself seems to understand the lowercase `sasl_plaintext` values, [HIDDEN]

**To Reproduce**
Steps to reproduce the behavior:
1. Setup SASL, but use lowercase `sasl_plaintext` as the security protocol.
2. See that SASL configs are not loaded via `getConsumerOptions()`

**Expected behavior**
I would expect the SASL configs to be loaded properly regardless of the casing of their values.

### Additional contract requirements

- SASL configuration must be loaded regardless of the casing of the security protocol value, including lowercase `sasl_plaintext`.
