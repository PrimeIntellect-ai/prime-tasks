Make `rarfile` dependency optional
The `rar` compression is proprietary.

It is only used to read rar of video files, which is very unlikely.

### Additional contract requirements

- `subliminal.exceptions.ArchiveError` is a public exception type that signals a failure to read an archive.
- `subliminal.core.scan_archive(path, name=None)` raises `ArchiveError` when an archive cannot be read:
  - for a path whose extension is not a supported archive extension, the error message is the file extension
    followed by ` is not a valid archive`, for example `"'.mp3' is not a valid archive"` and
    `"'.mkv' is not a valid archive"`.
  - when the archive contains no video, the error `args` are `('No video in archive',)`.
  - when a RAR archive requires a password, the error `args` are `('Rar requires a password',)`.
- `rarfile` is not a mandatory runtime dependency: subliminal must remain importable and usable when `rarfile` is not installed, including
  scanning a directory that contains a `.rar` file.
