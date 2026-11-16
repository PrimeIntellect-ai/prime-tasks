Provide a way to 'anonymize' line numbers when building a Snippet
In the rust test suite there's the option to replace line numbers in the diagnostics output with letters, so that changes in the output produce less noisy diffs.

With that flag enabled, the following

```
error: cannot concatenate a byte string literal
  --> $DIR/concat.rs:2:13
   |
 2 |     concat!(b'f');
   |             ^^^^
```

is turned into

```
error: cannot concatenate a byte string literal
  --> $DIR/concat.rs:2:13
   |
LL |     concat!(b'f');
   |             ^^^^
```

Any line number is replaced by `LL`, no matter the digits of that number.

AFAICT, rustc would currently have to implement its own `Snippet -> DisplayList` conversion, which would duplicate a lot of the conversion code just to anonymize the line numbers.

I think this would be nice to have inside `annotate-snippets` too, maybe as an option when constructing a Snippet? I believe other users of this library could also benefit from this option.

### Additional contract requirements

The public constructor `DisplayListFormatter::new` takes two boolean arguments: `new(color, anonymize_line_numbers)`. The first enables or disables ANSI colors. The second, when `true`, opts in to anonymizing displayed source-line labels: each displayed source-line number is rendered as `LL`, regardless of its original value. Anonymization must not change line and column coordinates in an initial file-location header. When `anonymize_line_numbers` is `false`, the formatter retains its existing non-anonymized output.
