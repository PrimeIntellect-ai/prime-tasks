[Bug] export-compiler-config flag requires Python file
### Is there an existing issue for this?

- [x] I have searched the existing issues

### Is this issue mentioned in the CHANGELOG?

- [x] I have searched the CHANGELOG and expect the bug to be reproducible on the `devel` branch

### Describe the bug

Since the flags were updated the FILE argument has become compulsory. This means that an arbitrary irrelevant (existing) FILE must be provided in order to use the `--export-compiler-config` flag

### Expected behavior

The FILE should be used as the export file, or no FILE should be required if the flag is used

### Add Screenshots

_No response_

### Record

- [x] I have read the [Contributing Guidelines](https://github.com/pyccel/pyccel/blob/devel/docs/CONTRIBUTING.md).
- [x] I have starred the repository

### Additional contract requirements

- The command-line flag `--export-compiler-config` is a boolean flag that takes no value. When it is supplied, the `FILE` positional argument is used as the path of the JSON file to write; the compiler configuration is written to that file and the command finishes successfully without translating or compiling `FILE`.
- If the `FILE` path has no extension, `.json` is appended to it to determine the output file name.
- If the `FILE` path has an extension other than `.json`, an error is emitted and the command exits with status `1`.
- `Compiler.export_compiler_info(self, compiler_export_filename: str | Path)` in module `pyccel.codegen.compiling.compilers` writes the compiler configuration as JSON to the given filename. It accepts both `str` and `Path` values, creates any missing parent directories of the target file, writes the file using UTF-8 encoding, returns `None`, and raises `OSError` if the file cannot be created.
