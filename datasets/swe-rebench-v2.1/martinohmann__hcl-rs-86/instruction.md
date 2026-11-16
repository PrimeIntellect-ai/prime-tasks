Panic attempting to parse an integer
Given the following HCL:

```
resource "test" "testing" {
  ids      = [module.instance.0.id]
}
```

It leads to this panic:

```
thread 'main' panicked at 'called `Result::unwrap()` on an `Err` value: ParseIntError { kind: InvalidDigit }', ~/.cargo/registry/src/github.com-1ecc6299db9ec823/hcl-rs-0.8.2/src/parser/mod.rs:342:32
```
