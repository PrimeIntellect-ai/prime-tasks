swift-format fails to parse valid swift code
The following snippet fails to parse in `swift-format` but `swiftc` is able to compile it:
```swift
func foo<E: Error, T>(a: T, b: T, body: (T, T) throws(E) -> T) throws(E) -> T {
  try body(a, b)
}

struct S: Error { }

let x = try foo(a: 0, b: 1) { a, b throws(S) in 2 }
print(x)
```

repro:

```console
# compile
$ xcrun -toolchain org.swift.59202405011a swiftc test.swift
$ ./test
2

# format
$ xcrun -toolchain org.swift.59202405011a swift-format format test.swift
/Users/rauhul/Desktop/test.swift:7:32: error: unexpected code ', b throws(S) in 2' in closure
```
