Delete empty ZARR chunks
**Is your feature request related to a problem? Please describe.**

Delete empty ZARR chunk files to have less files in a cube, to save memory and increase reading performance.

Also copying of large cubes with lots of empty chunks into object storage should be much faster if cubes are "pruned" beforehand.

**Describe the solution you'd like**

A CLI tool `xcube prune` that deletes empty chunk files from a given cube.

### Additional contract requirements

The `xcube prune` command takes a single `INPUT` argument (the path to a ZARR cube)
and accepts an optional `--dry-run` flag. With `--dry-run`, no block files are
deleted, but the command still reports what it would delete.

The command writes progress messages to standard output in exactly this form, one
message per line and in this order:

    Opening cube from '<INPUT>'...
    Identifying empty blocks...
    Deleting <n> empty block file(s) for variable '<VAR>'...
    Done, <total> block file(s) deleted.

Here `<INPUT>` is the cube path exactly as given on the command line, there is one
`Deleting ...` line per data variable (in dataset order) where `<VAR>` is the
variable name and `<n>` is the number of empty chunks found for it, and `<total>`
is the total number of block files deleted (or that would be deleted in a dry run).

A data chunk is empty when all of its values are NaN. A chunk containing any non-NaN value is not empty.
