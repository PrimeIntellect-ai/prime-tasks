Expose function compile to an object file
Currently, rustc's bootstrap uses `cc` to generate object file by asking it to generate a `.a` archive, discard the archive, and "guessing" where the temporary object files are to use them. Things like [this](https://github.com/rust-lang/rust/blob/c5208518faa423b96e6d1fecaa6428a2fa4eb9d1/src/bootstrap/src/core/build_steps/llvm.rs#L1214). This, however, has been broken since either #684 or #786, as bootstrap does not understand the hashing mechanism used by cc-rs. This prevents upgrading cc in rustc's bootstrap, which is not ideal as `cc` has since included some bugfixes that are necessary to properly handle some situations (such as [this](https://github.com/rust-lang/cc-rs/pull/676)).

I wonder if cc would accept a PR adding a public `Build::compile_objects()` function that would return a `Vec<Path>` of all the object files?

### Additional contract requirements

- Add a public method `Build::compile_intermediates(&self) -> Vec<PathBuf>` on the `cc::Build` type.
- It runs the compiler to produce the intermediate object files for the configured source files, without performing the final archive step.
- It returns the paths of the compiled object files, in the order the source files were added.
- When compiling a source file named `foo.c`, the generated object-file path must end with `d1fba762150c532c-foo.o`.
