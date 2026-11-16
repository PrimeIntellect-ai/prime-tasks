Can't combine async expectations with sync expectations in one test.
As soon as you make one async call in your tests, you can no longer use standard `expect(x).to(...)`.

The following will refuse to compile:

```swift
class MySpec: QuickSpec {
    override func spec() {
        it("") {
            await expect { await someAsyncFunction() }.to(...)
            expect(1).to(equal(1))
        }
    }
}
```

And in fact, you don't even have to try to combine async expectations with sync expectations. For example, the following will refuse to compile:

```swift
class MySpec: QuickSpec {
    override func spec() {
        it("") {
            await someAsyncFunction()
            expect(1).to(equal(1))
        }
    }
}
```

This is, I think, the swift compiler becoming confused by the overloaded use of `expect`. When I made AsyncExpectation, I duplicated all the forms of `expect`, which essentially results in the following:

- `func expect<T>(_ expression: @autoclosure @escaping () throws -> T?) -> SyncExpectation<T>`
- `func expect<T>(_ expression: @autoclosure @escaping () async throws -> T?) async -> AsyncExpectation<T>`

And I think swift is becoming confused by this overloading.

Which results in this incredibly disappointing user experience.
