Make the zero value useful
While updating [go-tlsconfig](https://github.com/PowerDNS/go-tlsconfig) to logr v1, I encountered an issue with how zero values of Logger are handled. These currently cause a panic when a method is called on them.

In go-tlsconfig a logr.Logger is an option that could be passed like this (pre-v1 code):

```go
type Options struct {
        ...
	Logr     logr.Logger
}

func New(ctx context.Context, opt Options) (*Foo, error) {
        if log == nil {
		log = SomeDefaultLogger()
	}
        ...
}
```

The caller can omit the Logr option if it is not interested in logging or has no preference for a logger, depending on the component.

Since v1 made the Logger a concrete struct instead of an interface, it is no longer possible to set or compare it to `nil`. If the caller omits the Logr, any log call will cause a panic.

The component also has no clean way to check if it received a zero value. It is possible to check  if `log.GetSink() == nil`, but this is a bit messy and easy to forget.

### Proposed solution

These problems can be avoided by making the zero value of a Logger useful, which is considered a good practise for Go values anyway. This makes the Logger safer and more convenient to use. Calling methods on a zero value would be equivalent to calling them on a Discard logger.

Additionally, a new `IsZero()` function would allow testing for the zero value so that a default logger can be assigned, if desired. This is similar to `Time.IsZero()` in the standard library.

The Options struct in the example above would remain the same and the New function would become:

```
func New(ctx context.Context, opt Options) (*Foo, error) {
        if log.IsZero() {
		log = SomeDefaultLogger()
	}
        ...
}
```

If the component is not interested in logging when a zero Logger is provided, it can still safely use that zero value and no longer needs to explicitly assign a Discard logger.

The Discard logger would remain as is and not be converted to a zero value. This allows a caller to explicitly disable logging without it would being overridden with some component-specific default logger.

I posted a PR with this change (#153).

### Alternatives

Changing the option to `*logr.Logger` is also undesirable, because this would require:

- the caller to explicitly take the address of a logger like `&log` to pass it as an option.
- the component to dereference the pointer like `*log` to use and pass it as a value.
