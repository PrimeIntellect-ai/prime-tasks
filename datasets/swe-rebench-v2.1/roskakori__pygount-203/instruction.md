Add generated files by name
## Story

As user I want files with certain names to be counted as "generated" instead of "unknown" so that I can treat them accordingly.

Examples: poetry.lock, uv.lock, \*.g.dart.

## Goals

- [ ] In the command line, the user can specify the names of generated files using the `--generated-names` option, which works similar to `--names-to-skip`.
- [ ] By default, the following files are recognized as "generated":
  - [ ] `*.g.dart`. This seems to be a popular convention, but not a official recommendation, though. Regardless, see for example "[Code Generation with Dart & Flutter: The Ultimate Guide](https://codewithandrea.com/articles/dart-flutter-code-generation/)".
  - [ ] `*.lock`, for example Python's `uv.lock` or Rust's [`Cargo.lock`](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html).
  - [ ] go's [`go.sum`](https://go.dev/ref/mod#go-sum-files).
  - [ ] npm's [`package-lock.json`](https://docs.npmjs.com/cli/v11/configuring-npm/package-lock-json) and `npm-shrinkwrap.json`.
  - [ ] pnpm's `pnpm-lock.yaml`.

There is probably many more, but this should be a good starting point.

Estimate: 2.5h

### Additional contract requirements

- By default, files matching `*.g.dart` are recognized as "generated", in addition to `*.lock`.
