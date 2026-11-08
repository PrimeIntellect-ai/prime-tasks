EXC_BAD_ACCESS extracting existential
This was partially solved in https://github.com/pointfreeco/swift-case-paths/issues/53 but it seems that the fix is needed for all object-bound existential types.

Here's a rudimentary case that reproduces the crash (tested with Xcode 13.1, iOS 13.5 simulator):
```swift
private protocol TestObjectProtocol: AnyObject {}

func testObjectBoundExistentialPayload() {
  class Class: TestObjectProtocol {}
  enum Enum {
    case int(Int)
    case objectBoundExistential(TestObjectProtocol)
  }
  let intPath = /Enum.int
  let object = Class()
  for _ in 1...2 {
      XCTAssertNil(intPath.extract(from: .objectBoundExistential(object)))
  }
}
```
