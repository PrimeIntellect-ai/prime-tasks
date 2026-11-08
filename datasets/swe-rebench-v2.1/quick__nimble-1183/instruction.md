Identity checking tests no longer compile on 13.7.0
- [x] I have read [CONTRIBUTING](https://github.com/Quick/Nimble/blob/main/CONTRIBUTING.md) and have done my best to follow them.

Seems the current 13.7.0 made our tests stop building, namely due to these changes:

[HIDDEN]

We have a test checking whether a delegate (of a protocol type) is identical to an expected object:

```swift
protocol OurDelegate: AnyObject { }
...
var delegate: (any OurDelegate)?
...
expect(delegate).to(be(someObject))
```

which is a valid scenario imho.

[HIDDEN]

### Additional contract requirements

When an optional value of a class-bound protocol existential contains a different object from the expected object, `be(expectedObject)` does not match it.
