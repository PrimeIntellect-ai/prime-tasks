EXC_BAD_ACCESS when extracting a `Result.success` from a failure, if the result is `Result<_, Error>`
This happens in 0.7.0, I haven't tried other releases.

I've encountered this crash in the wild, which I had to work around by not using case paths for any `Result` where the `Failure` generic type is `Error`. If you try to add this unit test to the test suite in this repo, you can reproduce it:

```swift
  func testExtractSuccessFromFailedResultWithErrorProtocolError() throws {
    struct MyError: Error {}
    let x = Result<String, Error>.failure(MyError())

    // since it's `Error`, execution traps at the following line with an EXC_BAD_ACCESS.
    // If the  result type was over `MyError`, it would work correctly.
    XCTAssertNil((/Result.success).extract(from: x))
  }
```

There must be some swift runtime issue with Error protocol types vs concrete types that conform to `Error`, since it works if the type is `Result<String, MyError>` instead. I'm not too well versed in the swift runtime details to know how to fix this, except to work around it by not using case paths for these kinds of `Result` types for now.

If the value was a `.success` instead of a `.failure`, extraction does not crash, only when trying to extract a `.success` from this specific kind of Result if the value is a `.failure`. Extracting a `.failure` from this value also seems to work as expected.

### Additional contract requirements

- Extracting the `.success` case from a `Result<String, Error>` whose value is a `.failure` must return `nil` and must not crash or trap, regardless of the concrete type of the wrapped error value.
- Extracting the `.success` case from a `Result<String, Error>` whose value is a `.success` must return the associated success value.
