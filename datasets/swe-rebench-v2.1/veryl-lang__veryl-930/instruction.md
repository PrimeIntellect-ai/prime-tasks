Naming convention of built-in namespaces
Now there are two built-in namespace: `$sv` and `std`.
One is prefixed by `$` and another isn't, it is inconsistent.

There are two ways to unified naming convention.

* `$sv` and `$std`: This is more clear that `$` means built-in namespace, but `$std` is bit long and noisy for the frequent usage.
* `sv` and `std`: Opposite to the above.

At the moment, I prefer `sv` and `std`.

### Additional contract requirements

The accepted resolution unifies the built-in namespaces on the `$`-prefixed
convention: `$sv` and `$std`. The earlier preference for the unprefixed
`sv`/`std` spelling is superseded.

- The standard library namespace is `$std`; `$std::<name>` must resolve to the
  standard library member `<name>` (for example `$std::fifo`).
- When emitting SystemVerilog, a member of the `$std` namespace is emitted with
  the `std_` prefix (for example `$std::fifo` is emitted as `std_fifo`).
