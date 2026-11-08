Endpoint path incorrect for router group index routes
When using a router group in combination with index routes, the endpoint path for those requests incorrectly (IMO) has a trailing slash:

```swift
let group = router.group("/users")
group.get(use: list)

func list(request: HBRequest) {
  // here I'd expect request.endpointPath to be "/users", but it is "/users/"
}
```

This might be a regression from https://github.com/hummingbird-project/hummingbird/pull/164.
