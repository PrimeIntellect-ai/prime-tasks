HookRequest.Headers and HookResponse.Headers maps need to be canonicalized
As discussed in #3554, attempting to access known header keys directly from the maps provided by:
* [HookRequest.Headers](https://github.com/google/go-github/blob/c099baf334af9b3362514dd9d3164c4be0097056/github/repos_hooks_deliveries.go#L45)
* [HookResponse.Headers](https://github.com/google/go-github/blob/c099baf334af9b3362514dd9d3164c4be0097056/github/repos_hooks_deliveries.go#L56)

using the [provided constant, canonicalized header keys](https://github.com/google/go-github/blob/c099baf334af9b3362514dd9d3164c4be0097056/github/messages.go#L36-L43) does not work when the external header keys do not exactly match the case of our provided constants.

There are two solutions to this problem:

Solution 1:
* canonicalize all header keys every time a `HookDelivery` struct is returned ([here](https://github.com/google/go-github/blob/c099baf334af9b3362514dd9d3164c4be0097056/github/repos_hooks_deliveries.go#L69), [here](https://github.com/google/go-github/blob/c099baf334af9b3362514dd9d3164c4be0097056/github/repos_hooks_deliveries.go#L95), and [here](https://github.com/google/go-github/blob/c099baf334af9b3362514dd9d3164c4be0097056/github/repos_hooks_deliveries.go#L116), plus six more locations).

Solution 2:
* add two new helper methods that would provide a [Header.Get](https://pkg.go.dev/net/http#Header.Get)-like experience for `HookRequest` and `HookResponse` such that the header key lookup is totally case insensitive (both for the search strings and for the contents of the map), like this:

```go
// GetHeader gets the value associated with the given key (ignoring key case).
func (h *HookRequest) GetHeader(key string) string {
  ...
}

// GetHeader gets the value associated with the given key (ignoring key case).
func (h *HookResponse) GetHeader(key string) string {
  ...
}
```

I'm open to either solution. @sparshev - do you have a preference?

This would be a great PR for any new contributor to this repo or a new Go developer.
All contributions are greatly appreciated!

Feel free to volunteer for any issue and the issue can be assigned to you so that others don't attempt to duplicate the work.
Also feel free to perform a code review on any PR that has the label "NeedsReview" - we appreciate those contributions too!
We have a `REVIEWERS` file that you could add your username to if you are willing to be contacted when reviews are needed.

Please check out our [CONTRIBUTING.md](https://github.com/google/go-github/blob/master/CONTRIBUTING.md) guide to get started. (In particular, please remember to `go generate ./...` and don't use force-push to your PRs.)

Thank you!

### Additional contract requirements

The required solution is Solution 2. It must add the following public methods in package `github`:

- `func (h *HookRequest) GetHeader(key string) string` on `HookRequest`.
- `func (h *HookResponse) GetHeader(key string) string` on `HookResponse`.

Each method returns the value associated with the given header key, ignoring the case of both the requested key and the keys present in the `Headers` map, and returns the empty string when no matching key exists.
