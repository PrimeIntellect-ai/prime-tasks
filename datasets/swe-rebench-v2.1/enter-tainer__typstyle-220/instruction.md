Custom tab size
I know that the canonical tabbing for Typst is "two spaces", but for a lot of users that's unusual. Thus, for all languages that recommend two-space, I (and a lot of programmers I know) use a four-space tabbing during development, and then turn it into two-space right before publishing, often automatically.

Because of that, I propose having a setting for tab size. I imagine it could be easy. As a last resort, it could be crutched as
[HIDDEN] or whatever its analogue in Rust is...

### Additional contract requirements

The formatter must provide a `--tab-width` command-line setting that controls the number of spaces used for each indentation level in formatted output.
