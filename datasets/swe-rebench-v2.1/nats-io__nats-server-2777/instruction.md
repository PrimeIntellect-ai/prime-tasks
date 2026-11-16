The "max_file_store" option cannot be quoted
## Defect

The server does not process a quoted string of the `max_file_store` option.  It'd be great it if could.

```bash
$ cat quoted.conf
jetstream {
  max_file_store: "200M"
}

$ nats-server -c quoted.conf
nats-server: quoted.conf:1:0: interface conversion: interface {} is string, not int64
```

Others like this should be checked as well...

### Additional contract requirements

- The JetStream storage options `max_file_store` and `max_memory_store` accept either a plain integer byte count or a quoted string size.
- A string size is a number followed by one of the suffixes `K`, `M`, `G` or `T`, using binary multipliers: `K` = 1024, `M` = 1024*1024, `G` = 1024*1024*1024 and `T` = 1024*1024*1024*1024. For example, `"200M"` means 200*1024*1024 bytes.
- An empty string is treated as zero.
- A value that is neither an integer nor a valid size string (for example a malformed string, an unsupported suffix, or a value that is neither an integer nor a string) is rejected with an error.
