tests should not fail when: $TMPDIR is set
The new test `TestAllDir` fails when the env variable `TMPDIR` is set to point to within the home directory.

The stripped table output contains: `$NKEYS_PATH No ~/tmp/nsc_test1638242485`
The test complains: `does not contain "$NKEYS_PATH Yes /home/myusercode/tmp/nsc_test1638242485"`

This has two different expectations of normalization.

### Additional contract requirements

The `nsc env` report must include the `XDG_CONFIG_HOME` and `XDG_DATA_HOME` environment variables.

The `nsc env` report must mark the `NKEYS_PATH` and `NSC_HOME` settings as deprecated by appending `(deprecated)` to their names.
