Error "proc-macro derive produced unparseable tokens" with nested macro call
I was working on updating [UniFFI](https://github.com/mozilla/uniffi-rs/) to the latest `main` branch of Askama, and ran into a case where the `#[derive(Template)]` seems to generate invalid code. Below is a reduced example:

```
use askama::Template;

#[derive(Template)]
#[template(source="

use askama::Template;

#[derive(Template)]
#[template(source="

    {%- macro outer(ctx) -%}
    {%- call inner(ctx, \"name\") -%}
    {%- endmacro -%}

    {%- macro inner(ctx, name) -%}
    {{ name }} = value;
    {%- endmacro -%}

    {%- call outer(ctx) -%}

", ext="txt", print="code")]
struct MacroBug {
    ctx: (),
}

impl MacroBug {
    #[cfg(test)]
    fn testme() -> String {
        MacroBug { ctx: () }.render().unwrap()
    }
}

#[cfg(test)]
mod test {
    use super::*;
    #[test]
    fn test_it() {
        assert_eq!(MacroBug::testme(), "name = value;")
    }
}
```

This compiles and runs correctly on the latest Askama release, but when compiled against current `main` ([b318d7cb](https://github.com/djc/askama/commit/b318d7cbcded2c6dfc66bbe19687f1246a9a9eab)) it gives an error:

```
error: expected pattern, found `,`
 --> src/lib.rs:4:10
  |
4 | #[derive(Template)]
  |          ^^^^^^^^ expected pattern
  |
  = note: this error originates in a derive macro (in Nightly builds, run with -Z macro-backtrace for more info)

error: proc-macro derive produced unparseable tokens
 --> src/lib.rs:4:10
  |
4 | #[derive(Template)]
  |          ^^^^^^^^
```

The issue seems to be in the code for calling the inner macro. The generated code front `print="code"` looks like:

```
impl ::askama::Template for MacroBug {
    fn render_into(&self, writer: &mut dyn ::std::fmt::Write) -> ::askama::Result<()> {
        {
            {
                let (, name) = (, ("name"));
```
