Default Option value in help text includes `Optional(…)`
the following option

```swift
@Option(default: true)
var doStuff: Bool?
```

would result in the following default value description:

```
(default: Optional(true))
```

This is counterintuitive and requires user to workaround it.
