[Structured logging] Stringify u64 attributes
### How do you use Sentry?

Sentry SaaS (sentry.io)

### SDK version

latest

### Steps to reproduce

Log something with an attribute with a value higher than max i64 and lower than max u64

### Expected result

Correct attribute value in Sentry, matching the one that is logged to the console.

### Actual result

serde serializes it as float and there can be loss of precision.
We should make sure that these values are actually serialized as string instead.
