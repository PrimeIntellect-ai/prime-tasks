qlc error - max limit cache eviction fails for no cwd write permissions
`qlc` uses the filesystem to store cursor information.

The result of `qlc` calls is discarded by Cachex, therefore it's possible to observe the following error logged - in case the current working directory is not writeable upon cursor/batch erase:

```
{:error, :qlc, {:file_error, ~c"appname-01_1_2222737.1", :eacces}}
```

Resulting with a silent failure of cache eviction.

I think the preferable approach would be to allow overriding qlc's `{tmpdir, TempDirectory}` configuration as per https://www.erlang.org/doc/man/qlc#common-options.
