RichDiagnostic should point to the source of the primary label
https://github.com/brendanzab/codespan/blob/master/codespan-reporting/src/term/views/source_snippet/mod.rs#L60#L66

https://github.com/brendanzab/codespan/blob/master/codespan-reporting/src/term/views/source_snippet/mod.rs#L87#L107

In SourceSnippet reporting, it tries to determine the max region of the error. Perhaps in previous versions this made sense, but in the latest version, the diagnostics are a PrimaryLabel + a list of other second labels (with notes and warnings, etc)

So it feels very peculiar to not just point to the PrimaryLabel's location in the span of the error message.

Consider this example from Rust:

```
error[E0308]: if and else have incompatible types
   --> path/to/my_file.rs:221:9
    |
218 | /     if (true) {
219 | |         5
    | |         - expected because of this
220 | |     } else {
221 | |         false
    | |         ^^^^^ expected integer, found bool
222 | |     };
    | |_____- if and else have incompatible types
    |
```

`SourceSnippet` would put this min/maxed box of ` path/to/my_file.rs:219:14` as the location, not `path/to/my_file.rs:221:9` which is the location of the primary label
