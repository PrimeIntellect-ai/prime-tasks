With duplicate subscriptions unsubscribing of one of the subs kills both records in Registry
### Environment

* Elixir version (elixir -v): Elixir 1.16.0 (compiled with Erlang/OTP 26)
* Absinthe version (mix deps | grep absinthe): 1.7.6
* Client Framework and version (Relay, Apollo, etc): Apollo, version is probably irrelevant

### Expected behavior
We want to subscribe to the same subscription twice: one subscription is alive throughout the lifecycle of the app (counter for notifications), second is only alive when a component rendering the content of notifications is open.

### Actual behavior
When subscribing to the same subscription twice (with different set of fields), unsubscribing of one of the subs kills the second sub.
[HIDDEN]
[HIDDEN]

### Additional contract requirements

- When two active subscriptions target the same subscription field, unsubscribing either one must leave the other registered and able to receive subsequent publications.
- This independent unsubscription behavior also applies when the subscriptions select different sets of fields.
