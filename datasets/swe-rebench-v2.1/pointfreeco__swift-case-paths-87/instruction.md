New CasePath initializer doesn't work with optional Root
I've just noticed that CasePaths created with the new `CasePath` initializer are unable to extract values from an optional `Root`. [HIDDEN]

You can reproduce the problem by performing the following change in the `testPathExtractFromOptionalRoot` test from
```swift
let path: CasePath<Authentication?, String> = /Authentication.authenticated
```
to
```swift
let path: CasePath<Authentication?, String> = CasePath(Authentication.authenticated)
```

and see the test fail afterwards. I'd expect the result to be the same after the change. The behavior is the same in Xcode 13.4 and Xcode 14b2.

I'm not sure at the moment what the right course of action would be other than moving to static functions instead of the initializer and how this should be reflected in the unit tests.

### Additional contract requirements

Case paths created from a no-payload case must also extract that case when the root is optional. This change must preserve extraction and embedding for case paths whose root is not optional.
