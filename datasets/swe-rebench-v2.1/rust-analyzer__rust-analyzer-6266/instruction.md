Document rust-analyzer diagnostics
We should document all our diagnostics in the manual (probably don't need a lot of text, just the diagnostic code and maybe an example message). We could probably generate this similarly to the assist documentation.

### Additional contract requirements

- Add a public function `generate_diagnostic_docs(mode: Mode) -> Result<()>` in the `xtask::codegen` module.
- Calling it generates the diagnostics documentation and writes it to `docs/user/generated_diagnostic.adoc`.
- The generated documentation lists every rust-analyzer diagnostic by its diagnostic code.
- `Mode::Overwrite` writes (replaces) the file; `Mode::Verify` returns an error if the file is out of date.
