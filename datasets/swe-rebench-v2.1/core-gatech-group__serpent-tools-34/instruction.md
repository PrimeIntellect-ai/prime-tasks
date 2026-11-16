Add more message types
Add some future/depreciated warnings that can either piggy back off the [python builtin warnings](https://docs.python.org/2/library/warnings.html) but also conform to our messaging methodology

### Additional contract requirements

- Provide a public decorator `depreciated(f)` in the module `serpentTools.settings.messages`. Applying it to a callable produces a callable that, when called, emits a warning and returns the result of the wrapped callable, passing through all positional and keyword arguments unchanged.
- Provide a public factory `willChange(changeMsg)` in the module `serpentTools.settings.messages`. It accepts a string describing an upcoming change and returns a decorator. Applying that decorator to a callable produces a callable that, when called, emits a warning and returns the result of the wrapped callable, passing through all positional and keyword arguments unchanged.
- The warning emitted when a decorated callable is invoked is observable through Python's builtin warnings mechanism and/or the project's messaging system.
