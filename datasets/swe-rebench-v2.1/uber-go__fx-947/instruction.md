Allow specifying fx.Module-specific custom loggers with WithLogger
Currently, passing `fx.WithLogger` to an `fx.Module` throws an error like this:

```
[Fx] ERROR              Failed to start: fx.WithLogger Option should be passed to top-level App, not to fx.Module
```

This isn't ideal because a library author that exports their app as an `fx.Module` cannot specify a custom logger whose scope applies to just their `Module`.

This tracks extending the current implementation of `WithLogger` option so that it can be passed directly to an `fx.Module`, such that when it is, it only affects the scope of that `Module`.

Internal Ref: GO-1488
