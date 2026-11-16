Origin line number is not correct when using a slice with `fold: true`
Here is a test case demonstrating the issue:

```rs
#[test]
fn test_origin_line_numbers_with_fold() {
    let snippets = Snippet {
        title: Some(snippet::Annotation {
            id: None,
            label: Some("oops"),
            annotation_type: snippet::AnnotationType::Error,
        }),
        footer: vec![],
        slices: vec![snippet::Slice {
            source: "First line\r\n\r\n\r\nSecond oops line",
            line_start: 1,
            origin: Some("<current file>"),
            annotations: vec![
                snippet::SourceAnnotation {
                    range: (23, 27),
                    label: "oops",
                    annotation_type: snippet::AnnotationType::Error,
                },
                snippet::SourceAnnotation {
                    range: (0, 5),
                    label: "First",
                    annotation_type: snippet::AnnotationType::Info,
                },
            ],
            fold: true,
        }],
        opt: Default::default(),
    };
    let expected = r#"error: oops
 --> <current file>:4:8
  |
1 | First line
  | ----- info: First
...
4 | Second oops line
  |        ^^^^ oops
  |"#;

    assert_eq!(DisplayList::from(snippets).to_string(), expected);
}
```

`--> <current file>:2:8` is printed instead of `--> <current file>:4:8`.
