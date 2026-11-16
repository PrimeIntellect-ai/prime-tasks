Option to enable strict duplicate detection
<!--
PLEASE DO NOT USE GITHUB ISSUES TO ASK QUESTIONS!

The JJWT team uses GitHub Issues only to track actionable work that requires changes to the JJWT codebase.

If you have a usability or general question about JJWT, please instead post your question to StackOverflow using the following JJWT-specific link:

https://stackoverflow.com/questions/ask?tags=jjwt&guided=false

To help ensure you receive a timely response, please follow the StackOverflow guidelines on how to ask a good question: https://stackoverflow.com/help/how-to-ask

Ok, now that that's out of the way - if you're still sure you want to create a feature request or enhancement, please fill in the sections below...
-->

**Is your feature request related to a problem? Please describe.**
For parsing, we are using the `JacksonDeserializer` via the constructor `public JacksonDeserializer(Map<String, Class<?>> claimTypeMap)`.
When parsing a JWT with duplicate properties, the last one will be used, and the rest are ignored. Although this behavior is allowed by the RFCs, we would prefer for the parser to throw an exception if there are duplicate keys.
In general, it can create vulnerabilities if e.g. different parsers are used in a stack, where some use the first item, and some use the last item, in cases of duplicates. This is of course not allowed in JWT context, but we would also like to fail fast, if the next parser fails.
[HIDDEN]
The problem is that there is no way to access the `objectMapper` in `JacksonDeserializer`.

**Describe the solution you'd like**
An option to enable `JsonParser.Feature.STRICT_DUPLICATE_DETECTION` on the `objectMapper` in `JacksonDeserializer`. Whether it be by adding a getter for the `objectMapper` or an extra constructor that also takes `JsonParser.Feature`s?

**Describe alternatives you've considered**
We could write our own implementation of `AbstractSerializer`, but it would be a copy of the `JacksonDeserializer` class except for enabling the strict duplicate detection.

**Additional context**
The RFCs allows both behaviors for parsing duplicates in both header and payload:
https://www.rfc-editor.org/rfc/rfc7515.html#section-4
https://www.rfc-editor.org/rfc/rfc7519#section-4
Strict duplicate detection:
https://fasterxml.github.io/jackson-core/javadoc/2.9/com/fasterxml/jackson/core/JsonParser.Feature.html#STRICT_DUPLICATE_DETECTION

### Additional contract requirements

- Parsing a JWT whose JSON object contains the same key more than once must fail with a `DeserializationException` when the parsing `JacksonDeserializer` was created with the no-argument constructor or with the `Map<String, Class<?>>` claim-type constructor. The exception's cause must mention the duplicated key name.
- The `JacksonDeserializer(ObjectMapper)` constructor uses the supplied `ObjectMapper` as the caller configured it. If the caller has enabled `JsonParser.Feature.STRICT_DUPLICATE_DETECTION` on that `ObjectMapper`, duplicate keys must be rejected with a `DeserializationException` as above. If the caller has not enabled it, the deserializer must not enable it, and duplicate keys are parsed as Jackson does by default (the last value is used).
