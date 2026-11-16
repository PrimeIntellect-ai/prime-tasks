Behaviour of joinpath when the second path has protocol
```
UPath('a').joinpath(UPath('s3:///b'))
```
This call will return `PosixUPath('/b')`, but
```
UPath('a').joinuri(UPath('s3:///b'))
```
will return `S3Path('s3:///b')`.

Maybe in `joinpath`, we should return just the second path when the second path has protocol (like in `joinuri`)?

### Additional contract requirements

When `joinpath` receives a path-like component with a non-empty protocol that differs from the base path, it raises `ValueError` rather than joining paths with incompatible protocols. The `/` operator raises the same error for the same mismatch. `joinuri` continues to select the second URI when the protocols differ.
