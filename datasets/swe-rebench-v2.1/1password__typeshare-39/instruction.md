Kotlin struct properties should be immutable
Currently in other languages (where it exists) typeshare emits properties that are immutable. In Kotlin, these are emitted as `var` which is mutable. To stay consistent, we should emit as `val`.

For example, this Rust type:
```rs
pub struct Foo {
    pub a: i8,
    pub b: i16,
    pub c: i32,
    pub e: u8,
    pub f: u16,
    pub g: u32,
}
```

produces this Swift type:

```swift
public struct Foo: Codable {
  public let a: Int8
  public let b: Int16
  public let c: Int32
  public let e: UInt8
  public let f: UInt16
  public let g: UInt32

  public init(a: Int8, b: Int16, c: Int32, e: UInt8, f: UInt16, g: UInt32) {
    self.a = a
    self.b = b
    self.c = c
    self.e = e
    self.f = f
    self.g = g
  }
}
```

and this Kotlin type:

```kt
data class Foo (
  var a: Byte,
  var b: Short,
  var c: Int,
  var e: UByte,
  var f: UShort,
  var g: UInt
)
```
