ReaderOptions should support BackoffPolicy similar to what was added for ProducerOptions and ConsumerOptions.
**Is your feature request related to a problem? Please describe.**
Reader implementation needs configurable backoff parameters.

**Describe the solution you'd like**
`ProducerOptions` and `ConsumerOptions` both support `BackOffPolicy` per #853 - we also need that functionality for `ReaderOptions`.

**Describe alternatives you've considered**
N/A

**Additional context**
Add any other context or screenshots about the feature request here.

### Additional contract requirements

- `ReaderOptions` (in package `pulsar`) must expose a field named `BackoffPolicy` of type `internal.BackoffPolicy` (import path `github.com/apache/pulsar-client-go/pulsar/internal`). When set, the reader must use it to determine the delay before each reconnection attempt.
- `ConsumerOptions` (in package `pulsar`) must expose a field named `BackoffPolicy` of type `internal.BackoffPolicy`. When set, the consumer must use it to determine the delay before each reconnection attempt.
- `ProducerOptions` (in package `pulsar`) must expose a field named `BackoffPolicy` of type `internal.BackoffPolicy`. When set, the producer must use it to determine the delay before each reconnection attempt.
- `internal.BackoffPolicy` is an interface with a single method `Next() time.Duration` that returns the delay to wait before the next reconnection attempt.
