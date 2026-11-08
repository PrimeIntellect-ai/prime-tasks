ExtensionPointChangedEvent `__repr__` says it was a TraitListEvent
Since Traits 6.1, `TraitListEvent` has its `__repr__` implemented. Envisage has an `ExtensionPointChangedEvent` that merely subclasses `TraitListEvent` to add an extension point id, and it does not reimplement the `__repr__`.

Consequently, when printing an instance of `ExtensionPointChangedEvent`, one may then think they are handling a `TraitListEvent`.

```
>>> print(event, type(event))
TraitListEvent(index=None, removed=[], added=[42, 'a string', True]) <class 'envisage.extension_point_changed_event.ExtensionPointChangedEvent'>
```

Reimplementing `__repr__` for `ExtensionPointChangedEvent` should fix this.

### Additional contract requirements

The string representation of an `ExtensionPointChangedEvent`, including when printed, must identify it as an `ExtensionPointChangedEvent` rather than a `TraitListEvent`, and include the identifier of the extension point that changed.
