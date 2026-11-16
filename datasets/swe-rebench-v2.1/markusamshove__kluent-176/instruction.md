Support for Instant assertions
It would be great if we had assertions for the [Instant](https://docs.oracle.com/javase/8/docs/api/java/time/Instant.html) class, similar to what’s available currently for ‘LocalDateTime’ and others.

If you agree this would not be a bad idea, I can prepare a PR for this.

### Additional contract requirements

- Provide an infix `Instant.shouldBeAfter(expected: Instant): Unit` assertion. It succeeds only when the receiver is later than `expected`; otherwise, it throws an `AssertionError`.
- Provide an infix `Instant.shouldBeBefore(expected: Instant): Unit` assertion. It succeeds only when the receiver is earlier than `expected`; otherwise, it throws an `AssertionError`.
