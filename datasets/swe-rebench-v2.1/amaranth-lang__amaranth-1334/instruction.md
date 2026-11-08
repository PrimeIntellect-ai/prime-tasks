Unclear error message on `m.domains.cd_tx = ClockDomain()`
One could reasonably write the following code:

```py
m.domains.cd_tx = ClockDomain()
```

This fails with:

```
NameError: Clock domain name 'rx' must match name in `m.domains.cd_rx += ...` syntax
```

It fails because the `cd_` prefix is stripped by `ClockDomain()` but not `m.domains.x = `. The correct syntax is is:

```py
m.domains.cd_tx = ClockDomain()
```

This is a rather confusing diagnostic and should be improved.

### Additional contract requirements

- For `m.domains.cd_rx = ClockDomain()`, raise a `NameError` with the exact message `Domain name should not be prefixed with 'cd_' in `m.domains`, use `m.domains.rx = ...` instead`. For `m.domains.foo = ClockDomain("bar")`, raise a `NameError` with the exact message `Clock domain name 'bar' must match name in `m.domains.foo = ...` syntax`.
- For `m.domains.cd_tx = ClockDomain()`, raise a `NameError` with the exact message `Domain name should not be prefixed with 'cd_' in `m.domains`, use `m.domains.tx = ...` instead`.
