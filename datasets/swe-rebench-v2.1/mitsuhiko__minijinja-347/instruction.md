`ops::int_div` panics on overflow
## Description

`ops::int_div` panics on overflow.

## Reproduction steps

1. Add a test case below into the mod tests block in minijinja/src/value/ops.rs.

```
    #[test]
    #[should_panic]
    fn test_int_div_overflow() {
        _ = int_div(&Value::from(i128::MIN), &Value::from(-1i128));
    }
```

2. Run `cargo test -- test_int_div_overflow`
3. It prints the following output:

```
running 1 test
test value::ops::tests::test_int_div_overflow - should panic ... ok
```

Additional helpful information:

- Version of minijinja: the latest commit https://github.com/mitsuhiko/minijinja/commit/ae9017ebe881374b329d0c821a2586621087d54a
- Version of rustc: 1.72.0 (5680fa18f 2023-08-23)
- Operating system and version: Ubuntu 22.04

## What did you expect

Should return `Err(failed_op("//", lhs, rhs))`.
I suppose we should use [HIDDEN] to check an overflow.
