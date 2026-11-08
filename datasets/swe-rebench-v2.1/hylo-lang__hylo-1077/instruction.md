Fix use of members declared in trait extensions
This program should compile:
```
trait P {}
extension P {
  fun foo() { print("a") }
}
conformance Int: P {}

public fun main() {
  let a = 1
  a.foo()
}
```
Commit: 15d598713e29d80a77262b774204ecdc22b5fa07
