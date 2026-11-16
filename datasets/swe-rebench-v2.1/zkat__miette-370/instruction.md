Converting a `Report` to a `Box<dyn Diagnostic>` wipes all `Diagnostic` information
I suspect this is a super subtle issue in the crazy vtable code, but here is a relatively compact reproduction of the issue:
```rust
use miette::{miette, Diagnostic, LabeledSpan, Severity};

fn main() {
    let report = miette!(
        severity = Severity::Error,
        code = "expected::rparen",
        help = "always close your parens",
        labels = vec![LabeledSpan::at_offset(6, "here")],
        url = "https://example.com",
        "expected closing ')'"
    );
    assert_eq!(report.to_string(), "expected closing ')'".to_owned());
    assert_eq!(report.severity(), Some(Severity::Error));
    assert!(report.code().is_some());
    assert!(report.help().is_some());
    assert!(report.labels().is_some());
    assert!(report.url().is_some());

    let report_ref: &dyn Diagnostic = report.as_ref();
    assert_eq!(report_ref.to_string(), "expected closing ')'".to_owned());
    assert_eq!(report_ref.severity(), Some(Severity::Error));
    assert!(report_ref.code().is_some());
    assert!(report_ref.help().is_some());
    assert!(report_ref.labels().is_some());
    assert!(report_ref.url().is_some());

    let report_box: Box<dyn Diagnostic> = report.into();
    assert_eq!(report_box.to_string(), "expected closing ')'".to_owned());
    assert_eq!(report_box.severity(), None);
    assert!(report_box.code().is_none());
    assert!(report_box.help().is_none());
    assert!(report_box.labels().is_none());
    assert!(report_box.url().is_none());
}
```

The `Error` / `Display` impl is still totally okay, and all of the `Diagnostic` stuff that goes though the `Deref` impl seems to work fine — both `.as_ref()` and calling things like `.code()` on a `Report` directly — so the issue does *not* seem to be present here:
```rust
impl Deref for Report {
    type Target = dyn Diagnostic + Send + Sync + 'static;

    fn deref(&self) -> &Self::Target {
        unsafe { ErrorImpl::diagnostic(self.inner.by_ref()) }
    }
}
```

**NOTE:** I'm now moving away from the example above, to the context where this issue occurs in my code!

The issue seems to come specifically from (I believe) somehow attaching the wrong vtable? Here the data of the error stays the same — the source code information is kept — but calling `.source_code()` seems to just fall back on the default `None` impl?
```rust
impl From<Report> for Box<dyn Diagnostic + Send + Sync + 'static> {
    fn from(error: Report) -> Self {
        dbg!("impl From<Report> for Box<dyn Diagnostic + Send + Sync + 'static>");
        dbg!(&error);
        dbg!(error.source_code().is_some());
        let outer = ManuallyDrop::new(error);
        unsafe {
            [HIDDEN]
            dbg!(&res);
            dbg!(res.source_code().is_some());
            res
        }
    }
}

```
Outputs, in my case:
```
[/home/tll/.cargo/git/checkouts/miette-68017d45f967249d/5f42f10/src/eyreish/error.rs:750:9] "impl From<Report> for Box<dyn Diagnostic + Send + Sync + 'static>" = "impl From<Report> for Box<dyn Diagnostic + Send + Sync + 'static>"
[/home/tll/.cargo/git/checkouts/miette-68017d45f967249d/5f42f10/src/eyreish/error.rs:751:9] &error = Error {
    source_code: NamedSource {
        name: "test",
        source: "<redacted>",
        language: None,
    ,
    errors: [
        Unexpected {
            span: Span(
                0,
                49,
            ),
            kind: "node",
            message: "unexpected node `P`",
        },
        MissingNode {
            message: "child node `elements` is required",
        },
    ],
}
[/home/tll/.cargo/git/checkouts/miette-68017d45f967249d/5f42f10/src/eyreish/error.rs:752:9] error.source_code().is_some() = true
[/home/tll/.cargo/git/checkouts/miette-68017d45f967249d/5f42f10/src/eyreish/error.rs:758:13] &res = Error {
    source_code: NamedSource {
        name: "test",
        source: "<redacted>",
        language: None,
    ,
    errors: [
        Unexpected {
            span: Span(
                0,
                49,
            ),
            kind: "node",
            message: "unexpected node `P`",
        },
        MissingNode {
            message: "child node `elements` is required",
        },
    ],
}
[/home/tll/.cargo/git/checkouts/miette-68017d45f967249d/5f42f10/src/eyreish/error.rs:759:13] res.source_code().is_some() = false
```

The `error` and `res` structs remain the same, but calling the `.source_code()` method does not!

Any pointers on where to start fixing this would be excellent! The unsafe vtable code is beyond anything I've ever done in Rust, so figuring it out is a gradual process...

### Additional contract requirements

- Converting a `Report` into a `Box<dyn Diagnostic>` must preserve the diagnostic information and behavior available from the original report, including its severity, code, help, labels, and URL.
- If the original diagnostic provides source code, the boxed diagnostic must continue to provide that source code with its contents preserved.
