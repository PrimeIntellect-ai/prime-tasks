dump failed if there is a nil value
![image](https://user-images.githubusercontent.com/1251192/69246663-10c4bf80-0be4-11ea-9d55-842be8348590.png)
I am using Swift 5.1 and Xcode 11.2.1.

I try to debug the Yams, and it throw a error:
```swift
private func represent(_ value: Any) throws -> Node {
    if let string = value as? String {
        return Node(string)
    } else if let representable = value as? NodeRepresentable {
        [HIDDEN]
    }
    throw YamlError.representer(problem: "Failed to represent \(value)")  // -> print "Failed to represent nil"
}

extension Optional: NodeRepresentable {
    public func represented() throws -> Node {
        switch self {
        case let .some(wrapped):
            [HIDDEN]
        case .none:
            return Node("null", Tag(.null))
        }
    }
}
```

Is it a bug?

### Additional contract requirements

- `Yams.dump(object:)` must succeed for a value that contains a null (nil) entry rather than throwing, and the resulting YAML must represent the same value: reloading it with `Yams.load(yaml:)` yields an equivalent object with the null entry preserved.
- The exact spelling of the null scalar (for example `null` or `~`) and the mapping formatting are not specified.
- `Node(Int??.some(nil))` must equal `"null"`.
