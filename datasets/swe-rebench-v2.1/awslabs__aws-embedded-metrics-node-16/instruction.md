Calling flush would reset the namespace as well
Documentation for flush()

>flush()
Flushes the current MetricsContext to the configured sink and resets all properties, dimensions and metric values. The namespace and default dimensions will be preserved across flushes.

Namespace is set on the context and at the end of flush, context is set back to empty.

Either the documentation or the behavior of flush should be updated.

### Additional contract requirements

- The behavior of `flush()` must be updated so that the namespace is preserved across flushes. After each `flush()`, the logger retains its namespace, while metric values are reset.
