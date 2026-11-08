Is there a way to pull labels from a collection using proc macros?
Good day!

I have an enum with `#[derive(Diagnostic)]`.  I am trying to add an error type, which can have several spans sourced from a collection:

```Rust
pub enum ShellError {
    ...
    #[error("{0}")]
    #[diagnostic()]
    GenericError(
        String,
        #[label("{1}")]
        Vec<SourceSpan>,  // a vector with several spans
    ),
```

Is there a way to achieve this with proc macros?

### Additional contract requirements

- A field whose type is a collection of spans (for example `Vec<SourceSpan>`) is marked as a collection of labels by adding the `collection` keyword to its `label` attribute, as in `#[label(collection, "text")]`. Each item of the collection produces one label; when an item does not carry its own label text, the text from the attribute is used.
- `labels()` yields the labels from ordinary `#[label]` fields before the labels from `#[label(collection, ...)]` fields. Collection fields are yielded in field declaration order, and the items of each collection are yielded in the collection's iteration order.
- The collection form is supported for structs, for named-field enum variants, and for tuple enum variants (including the tuple-variant shape shown in the example above).
