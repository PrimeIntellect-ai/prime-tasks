Move file-specific options under OutFile
Similarly to #210, I think it's worth moving file-specific options under `OutFile::Path` variant.

(Just raising this as an issue for tracking before a major release cut.)

### Additional contract requirements

- `oxipng::OutFile` must expose a variant `None` that selects "pretend" mode: the optimizer computes the optimized result but writes no output file.
- `oxipng::OutFile::Path` must be a struct-style variant with a `path: Option<PathBuf>` field and a `preserve_attrs: bool` field. `path` is the destination file path, where `None` means overwrite the input file. `preserve_attrs` controls whether the output file retains the input file's permissions and timestamps.
- `oxipng::OutFile` must provide a constructor `OutFile::from_path(path: PathBuf) -> OutFile` that produces an `OutFile::Path` value carrying the given path with attribute preservation disabled.
