Deprecate WebHookPayload
The `PushEvent` type was originally added in June 2013 in beaff13913b3dd17651e12f622473b1fb99756a1.  I then added the `WebHookPayload` type a month later in 023e8db8cbba83d90a62e2e546a96d3dcecbbce4.  I honestly am not sure why I did that, since they are effectively duplicates.  Maybe it wasn't clear at that point that we should be using the same types for webhook payloads and activity events?  Or maybe I just wasn't thinking.

In any event, #302 reminded me that we've updated `PushEvent` to include a variant of `Repository` that has a string Organization filed (see d722750ab19bf6318a2c8dfad8d4aa034779aa8f), but the same update was never made to `WebHookPayload`.  Instead of fixing that, I think we should probably just deprecate `WebHookPayload` and point people to `PushEvent` instead.

### Additional contract requirements

- The deprecated names `WebHookPayload`, `WebHookCommit`, and `WebHookAuthor` must be aliases of `PushEvent`, `HeadCommit`, and `CommitAuthor` respectively: each deprecated name must denote exactly the same type as its replacement, so that values are interchangeable between the two names.
- `PushEvent` must expose the webhook action through a field named `Action` and a method `GetAction() string` on `*PushEvent` that returns the `Action` value when the receiver and the field are non-nil, and the empty string otherwise.
- String representations must identify `WebHookPayload`, `WebHookCommit`, and `WebHookAuthor` values as `github.PushEvent`, `github.HeadCommit`, and `github.CommitAuthor`, respectively. For the specified values, the exact outputs are `github.PushEvent{Ref:"r"}`, `github.HeadCommit{ID:"1"}`, and `github.CommitAuthor{Name:"n"}`.
- `PushEvent.String()` must include the `Action` field and render it after `DistinctSize` and before `After`.
