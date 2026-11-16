[DateRangeField] [HIDDEN] for fix the behavior when receive an empty value
The internal state may impact in situations when the component receives external values ​​and it's state is controlled by, for example, a form.

### Additional contract requirements

- When `DateRangeField` is controlled by an external value, emitted changes must not include stale values from a previously selected range. In particular, when the external range is empty and the user changes only one endpoint, the other endpoint must remain unset in the emitted range.
