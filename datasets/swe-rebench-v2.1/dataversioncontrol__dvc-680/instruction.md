Checkout single file
It would be great if the `dvc checkout` command could support checking out only a single file. This is useful when a file is accidentally changed or removed.

### Additional contract requirements

- The `dvc checkout` command accepts zero or more target DVC stage files as
  positional arguments, e.g. `dvc checkout foo.dvc`. When one or more targets
  are supplied, only the stages for those targets are checked out; when no
  target is supplied, all stages are checked out.
