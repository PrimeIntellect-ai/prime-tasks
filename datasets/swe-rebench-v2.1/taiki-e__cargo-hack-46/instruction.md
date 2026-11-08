Documentation for `--skip` is incorrect
The documentation claims that it takes a "Space-separated list of features to skip", but it actually appears to want a comma-separated list:

```console
> cargo hack --skip 'all all-implementations all-algorithms' --feature-powerset check
[...]
info: running `cargo check --no-default-features --features all,all-implementations,deflate,futures-bufread` on async-compression (31/4097)
[...]
```

```console
> cargo hack --skip 'all,all-implementations,all-algorithms' --feature-powerset check
[...]
info: running `cargo check --no-default-features --features deflate,futures-write,lzma` on async-compression (23/513)
[...]
```

### Additional contract requirements

The `--skip` option must accept a space-separated list of features, as its documentation claims, in addition to the comma-separated form. For example, both `--skip a,b` and `--skip "a b"` must skip the features `a` and `b`.
