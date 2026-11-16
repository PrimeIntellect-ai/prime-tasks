__ gets lost from labels
The starlark-rust library uses this code, specifically at https://github.com/facebookexperimental/starlark-rust/blob/13bec61a44dd2ec268403e1d6da4401ea76a3f12/starlark/src/errors/mod.rs#L205-L219. The relevant fragment is:

```rust
    let snippet = Snippet {
        title: Some(Annotation {
            label: Some(annotation_label),
            id: None,
            annotation_type: AnnotationType::Error,
        }),
        footer: Vec::new(),
        slices: slice.map(|s| vec![s]).unwrap_or_default(),
        opt: FormatOptions {
            color,
            ..Default::default()
        },
    };

    DisplayList::from(snippet)
```

However, if we have a label containing `__`, then that text gets lost from the label. [HIDDEN] That behaviour was super surprising. I can't find it documented. There seems to be no way to turn it off, and no way to apply escaping to stop it happening. Can you suggest how I might get it so that errors don't get changed as they are rendered?
