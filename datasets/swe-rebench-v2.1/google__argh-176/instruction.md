Error for long names misses some validation constraints
I had this compiler error just now:

```
error: Long names must be lowercase
  --> ../../src/diagnostics/validator/logs/sink/src/main.rs:49:27
   |
49 |     #[argh(option, long = "ignore_tag")]
   |
```

The option name *is* lowercase, but it has an underscore that argh wasn't happy with. Replacing it with a dash made the macro happy. I think the error message should probably list the specific way that the identifier doesn't work.

### Additional contract requirements

- For a long name that contains invalid characters, emit the diagnostic `Long names may only contain lowercase letters, digits, and dashes`.
