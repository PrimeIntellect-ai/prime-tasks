Support local image registry
Not once we've been asked how to use local SIF images to create pods. Should be considered as enhancement request?

### Additional contract requirements

- The local file domain is exposed as `singularity.LocalFileDomain` and its value is the string `local.file`.
- `ParseRef` recognizes references prefixed with `local.file` and returns a `*Reference` whose `URI()` is `local.file` and whose `Tags()` contains the full reference string (for example `local.file/home/sasha/my.sif`).
- `NormalizedImageRef` preserves the path of a `local.file` reference and strips a trailing `:latest` tag (for example `local.file/home/sasha/my.sif:latest` becomes `local.file/home/sasha/my.sif`).
- `Pull` with a `LocalFileDomain` reference to an existing file returns an `*Info` whose `Path` is that local file path (the file is used in place, not copied) and whose `Ref` is the passed reference. If the file does not exist, the returned error contains `no such file or directory`.
- `Info.Remove` on an image whose reference is `LocalFileDomain` is a no-op: it returns nil and leaves the file on disk.
- `Reference.URI` returns the empty string when called on a nil receiver.
