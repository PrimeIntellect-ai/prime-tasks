Unable to decode nested `multipart` array.
<!-- 🚀 Thank you for contributing! --->

### Describe the bug

```swift
struct Payload: Content {
    struct NestedPayload: Content {
        let name: String
        let age: Int
    }
    let nestedPayload: [NestedPayload]
}

let encoder = FormDataEncoder()
let encoded = try encoder.encode(Payload(nestedPayload: [.init(name: "abc", age: 10),
                                                         .init(name: "def", age: 20)]),
                                 boundary: "-")
let decoder = FormDataDecoder()
let decoded = try decoder.decode(Payload.self, from: encoded, boundary: "-")

```
got output `[ WARNING ] Value required for key 'nestedPayload.0.age'.`

### Environment

<!-- We must know your exact environment or it is very difficult to help. -->
<!-- Hint: use `vapor --version` in the root directory of your Vapor project. -->

* Vapor Framework version: 4.27.0
* Multipart-Kit Framework version: 4.2.1
* Vapor Toolbox version: 18.3.3
* OS version: Mac OS 11.3

### Additional contract requirements

- When encoding array entries, use zero-based numeric bracket indices in multipart part names, such as `array[0]`, `array[1]`, and `array[2]`.
