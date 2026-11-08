None value is converted to string when passed down to filter
## Description

I made a custom filter like:

```rust
fn my_filter(value: Option<String>) {}
```

and use it in a template, where the filter is applied for a field of a struct. That field has `None` value, but the filter got `Some("none")`.

To demonstrate the issue, I created a test case here:

https://github.com/hongquan/minijinja/blob/test/filter_expecting_optional_string/minijinja/tests/test_templates.rs#L534

## Reproduction steps

Please run the test case above.

Additional helpful information:

- Version of minijinja: v1.0.4
- Version of rustc: v1.70
- Operating system and version: Ubuntu 22.04

## What did you expect

The filter get `None` as its argument.

[What you think should have happened]

### Additional contract requirements

- A filter parameter of type `Option<T>` receives `None` when the argument is an undefined value, exactly as it does for the `none` value.


- - A filter parameter of type `Option<String>` receives the string `"wat"` as `Some("wat")`.
