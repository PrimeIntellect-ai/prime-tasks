Add file validators for File field
Add `FileType` and `FileSize` validators.

### Additional contract requirements

`FileType` determines a file's type from the final filename extension. Its permitted extensions are supplied by the caller as an iterable; comparisons are case-insensitive, and a missing or unpermitted extension is invalid.

`FileSize` accepts optional lower (`min`) and upper (`max`) size bounds as human-readable size strings. Values are compared with the uploaded file's byte length; `B`, decimal units such as `KB` and `MB`, and binary units such as `KiB` and `MiB` are supported. Bounds are inclusive by default. The lower bound’s inclusivity is controlled by `min_inclusive`, and the upper bound’s inclusivity is controlled by `max_inclusive`; each defaults to `True` and can be set independently.
