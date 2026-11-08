Scope::getTransaction returns null when Transaction isn't sampled
### Environment

How do you use Sentry?
Sentry SaaS (sentry.io)

Which SDK and version?
sentry-php@3.4.0

### Steps to Reproduce

1. initialize sentry with a very low sample rate for easier repro
2. call `$transaction = startTransaction`
3. call `SentrySdk::getCurrentHub()->setSpan($transaction)`
4. call `SentrySdk::getCurrentHub()->getTransaction()`

### Expected Result

I expected to get the instance of the Transaction I just started.

### Actual Result

`getTransaction` returned null because [HIDDEN].

This behavior is not documented anywhere, I think it would suffice to add a note to the `Hub::getTransaction` method that if it's not sampled it will return null.

### Additional contract requirements

- When a Transaction is attached to the active Scope, `Hub::getTransaction()` returns that same Transaction, whether or not it is sampled. It returns `null` when no Transaction is attached.
