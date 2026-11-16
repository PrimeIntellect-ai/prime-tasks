regression: rustfmt using input from stdin emits empty output when using `#![rustfmt::skip]`
Since #5094 - rustfmt now emits nothing to stdout if reading a file with `#![rustfmt::skip]` is provided via stdin.

For example, running `echo '#![rustfmt::skip]\n\nfn main() { }'  | rustfmt` no longer emits anything to stdout.

Rust-analyzer uses rustfmt to format files, and sends rustfmt the file contents to format via stdin.

This has caused an interesting issue, where rustfmt emits nothing, so rust-analyzer deletes the contents of the file being formatted: https://github.com/rust-lang/rust-analyzer/issues/12458
