Reconciliation of `undefined` `from`s is too restrictive
We are currently failing to reconcile a future with its execution state if its `from` is `undefined`, and the execution state's `from` is different from the `defaultSender` yet included in `accounts`. This case should be allowed.
