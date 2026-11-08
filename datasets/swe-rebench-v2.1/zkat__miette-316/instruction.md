Rendering bug on small spans in large spans
While using miette, I found a small but significant rendering bug in rendering arrows. The picture below shows what it looks like:
![image](https://github.com/zkat/miette/assets/22172241/c5c9ef87-80f8-4537-b74c-dcd5e80c3d26)

Of course, I can't just give you just that image to go on, so I made a minimal example:

```rust
#[derive(Error, Debug, Diagnostic)]
#[error("oops!")]
#[diagnostic(severity(Error))]
struct MyBad {
    #[source_code]
    src: NamedSource,
    #[label("big")]
    big: SourceSpan,
    #[label("small")]
    small: SourceSpan,
}
let err = MyBad {
    src: NamedSource::new("issue", "\
if true {
    a
} else {
    b
}"),
    big: (0, 32).into(),
    small: (14, 1).into(),
};
let out = fmt_report(err.into());
println!("Error: {}", out);

```
This prints:
```rust
r#"  × oops!
   ╭─[issue:1:1]
 1 │ ╭─▶ if true {
 2 │ │╭▶     a
   · ││    ┬
   · ││    ╰── small
 3 │ │   } else {
 4 │ │       b
 5 │ ├─▶ }
   · ╰──── big
   ╰────
"#
```

while I expected it to print:

```rust
r#"  × oops!
   ╭─[issue:1:1]
 1 │ ╭─▶ if true {
 2 │ │       a
   · │       ┬
   · │       ╰── small
 3 │ │   } else {
 4 │ │       b
 5 │ ├─▶ }
   · ╰──── big
   ╰────
"#

```

As you can see, this looks a bit like a test, which is exactly what I wrote and contributed as a pull request so the bug is reproducible. See #316.
