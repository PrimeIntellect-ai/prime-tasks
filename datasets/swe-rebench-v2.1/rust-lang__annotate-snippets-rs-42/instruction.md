Off-by-one error in multiline error highlights
In both cases, the highlight begins at letter `e` and ends at letter `l`. In the one-line case, it is correct:
```
error: oops
 --> <current file>:1:6
  |
1 | abcd efgh ijkl mnop
  |      ^^^^^^^^^ oops
  |
```
But in multiple lines it is off by one - the end pointer points to one past the end rather than the last character of the highlight:
```
error: oops
 --> <current file>:1:6
  |
1 |   abcd efgh
  |  ______^
2 | | ijkl mnop
  | |_____^ oops
  |
```
I could propose code but I'm not sure I'll get all the details of continuations right since I haven't used those and am not certain of the desired behavior. Here's the issue presented as a test case.
```rust
use annotate_snippets::{display_list::DisplayList, snippet};
use snippet::Snippet;

#[test]
fn with_space_works() {
    let snippets = Snippet {
        title: Some(snippet::Annotation {
            id: None,
            label: Some("oops"),
            annotation_type: snippet::AnnotationType::Error,
        }),
        footer: vec![],
        slices: vec![snippet::Slice {
            source: "abcd efgh ijkl mnop",
            line_start: 1,
            origin: Some("<current file>"),
            annotations: vec![snippet::SourceAnnotation {
                range: (5, 14),
                label: "oops",
                annotation_type: snippet::AnnotationType::Error,
            }],
            fold: true,
        }],
        opt: Default::default(),
    };
    let expected = r#"error: oops
 --> <current file>:1:6
  |
1 | abcd efgh ijkl mnop
  |      ^^^^^^^^^ oops
  |"#;
    assert_eq!(DisplayList::from(snippets).to_string(), expected);
}

#[test]
fn with_newline_fails() {
    let snippets = Snippet {
        title: Some(snippet::Annotation {
            id: None,
            label: Some("oops"),
            annotation_type: snippet::AnnotationType::Error,
        }),
        footer: vec![],
        slices: vec![snippet::Slice {
            source: "abcd efgh\nijkl mnop",
            line_start: 1,
            origin: Some("<current file>"),
            annotations: vec![snippet::SourceAnnotation {
                range: (5, 14),
                label: "oops",
                annotation_type: snippet::AnnotationType::Error,
            }],
            fold: true,
        }],
        opt: Default::default(),
    };
    let expected = r#"error: oops
 --> <current file>:1:6
  |
1 |   abcd efgh
  |  ______^
2 | | ijkl mnop
  | |____^ oops
  |"#;

    assert_eq!(DisplayList::from(snippets).to_string(), expected);
}
```

### Additional contract requirements

For an annotation that spans multiple lines, the end marker is placed at the last highlighted character, not one character past it. The multiline example in the description above that shows the end marker one character past the highlight is the incorrect rendering. The rendering of an annotation contained within a single line is unchanged.
