Remove `@escaping` attribute from `ReceivedArguments` and `ReceivedInvocations`
If the protocol contains func like this:
```swift
func foo(_ completion: @escaping () -> Void)
```
`ReceivedArguments` and `ReceivedInvocations` are throwing `@escaping attribute may only be used in function parameter position` errors
