[FEATURE] Implement transaction context
# We should implement transaction context propagation

## What is transaction context?

[From the spec:](https://openfeature.dev/specification/sections/evaluation-context#33-context-propagation)
Transaction context is a container for transaction-specific evaluation context (e.g. user id, user agent, IP).
Transaction context can be set where specific data is available (e.g. an auth service or request handler) and by using the transaction context propagator it will automatically be applied to all flag evaluations within a transaction (e.g. a request or thread).

Transaction context has been added in the following PR: https://github.com/open-feature/spec/pull/227

## Examples:

### Implementation
The JS SDK implementation is implemented as a POC that is currently being hardened.
https://github.com/open-feature/js-sdk/blob/main/packages/server/src/transaction-context/transaction-context.ts

### Usage
An example usage for the JS SDK implementation of the feature is the usage for propagating HTTP request information in the NestJS SDK.
https://github.com/open-feature/js-sdk/blob/main/packages/nest/src/evaluation-context-interceptor.ts#L31

### Additional contract requirements

- When evaluation context is merged for a flag evaluation, duplicate keys are resolved in the order: API (global; lowest precedence) < transaction < client < invocation < before hooks (highest precedence).
- The API exposes `setTransactionContext(EvaluationContext)` to set the current transaction context through the registered propagator.
- The API exposes `setTransactionContextPropagator(TransactionContextPropagator)` to register the propagator used for evaluations.
- NoOpTransactionContextPropagator is a public implementation of TransactionContextPropagator whose getTransactionContext() returns an empty (non-null) EvaluationContext and whose setTransactionContext(EvaluationContext) has no effect.
