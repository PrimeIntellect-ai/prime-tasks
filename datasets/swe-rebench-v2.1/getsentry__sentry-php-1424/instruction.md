Add `beforeSendTransaction`
### Problem Statement

Similar to `beforeSend`, we will add `beforeSendTransaction` to allow people to strip Pii or drop transactions before they are sent to Sentry.

### Solution Brainstorm

https://github.com/getsentry/sentry-javascript/pull/6121

### Additional contract requirements

Configure the transaction callback with the `before_send_transaction` client option. Invoke it for transaction events, not ordinary events. Send the event it returns when it returns an event, and do not send the transaction when it returns null.
