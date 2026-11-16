BatchResponse implementation makes testing difficult.
  * Operating System version: N/A
  * Firebase SDK version: 2
  * Library version: 6.12.2
  * Firebase Product: Messaging

#### Description:

BatchResponse is implemented as a final class with a package-private constructor. As such, this means that as a consumer of the library I have to either wrap the response object or use reflection to make it testable.

#### Steps to reproduce:

```java
// This will not compile
new BatchResponse(responses);
```

#### Suggestions

I would be happy to submit a PR for this but I would like guidance on implementation preference.

[HIDDEN]
c) [HIDDEN] This doesn't seem like a useful change.

### Additional contract requirements

Library consumers must be able to create a test double for batch-send results with a standard mocking library (for example Mockito) and pass it to code typed to the batch response, without reflection or a wrapper.
