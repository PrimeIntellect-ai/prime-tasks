Are labels in narratable report handler right?
Here is the snippet from the test:
```rust
    let src = "source\n  👼🏼text\n    here".to_string();
    let err = MyBad {
        src: NamedSource::new("bad_file.rs", src),
        highlight: (9, 6).into(),
    };
    let out = fmt_report(err.into());
    println!("Error: {}", out);
    let expected = r#"oops!
    Diagnostic severity: error
Begin snippet for bad_file.rs starting at line 1, column 1
snippet line 1: source
    label starting at line 1, column 1: this bit here
snippet line 2:   👼🏼text
snippet line 3:     here
diagnostic help: try doing it better next time?
diagnostic code: oops::my::bad
"#
```
The highlight (9, 6) should be on line 2 column 3 I think. No? Actually I've noticed this on my own example which is very similar, the span is on the middle of the 18th line, where snippet starts from 17th. But it prints "label starting at line 17, column 1" (so looks like sticks always to the first column of the first displayed line).

Am I misunderstanding narratable handler?

### Additional contract requirements

The narratable report handler reports each label on the source line it applies to, using the label's actual 1-based line and column in the source:

- A label whose span lies within a single line is reported as `label at line <line>, columns <start> to <end>`, where `<start>` and `<end>` are the 1-based columns of the first and last characters of the span. A label whose span is empty is reported as `label at line <line>, column <column>`.
- A label whose span starts on a line and continues onto a later line is reported on its starting line as `label starting at line <line>, column <column>`.
- A label whose span ends on a line after starting on an earlier line is reported on its ending line as `label ending at line <line>, column <column>`.
- When a label has text, the text is appended after the position as `: <text>`.
