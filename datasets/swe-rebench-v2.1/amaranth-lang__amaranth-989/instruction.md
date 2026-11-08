`PureInterface.__repr__` should use the actual class name rather than always using "PureInterface"
The `__repr__` method was added in https://github.com/amaranth-lang/amaranth/pull/982, with this bug.

While writing the documentation I discovered that it is reasonably useful to inherit from `PureInterface` for really simple custom interfaces, and that we should probably recommend that. This inheritance pattern also matches up with what we'll do for `Component`.
