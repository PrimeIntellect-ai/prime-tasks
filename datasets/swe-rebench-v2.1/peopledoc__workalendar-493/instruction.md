Registry API: alias `get_calendar_class` into `get()`
This is a substask of #375

``get_calendar_class()`` would be aliased to ``get()``, deprecated (and then removed).

### Additional contract requirements

- `IsoRegistry.get(iso_code)` returns the calendar class registered for `iso_code`, or `None` when the code is unknown.
- `IsoRegistry.get_calendar_class(iso_code)` keeps working and returns the same result as `get(iso_code)`.
- Calling `IsoRegistry.get_calendar_class(iso_code)` emits a `DeprecationWarning`, signalling that the method is deprecated and will be removed in a future release.
