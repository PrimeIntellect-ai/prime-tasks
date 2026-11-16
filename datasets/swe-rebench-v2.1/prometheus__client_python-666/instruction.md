No error on missing labels for Gauge.set_function()
If I try to assign a function to a Gauge using `set_function()`, the Prometheus library does not error even if the labels are missing.

This code should error, but it does not:

```python
import prometheus_client

processed_input_messages = prometheus_client.Gauge(
    name="my_gauge",
    documentation="A generic Gauge.",
    labelnames=["a", "b"],
)

if __name__ == '__main__':
    # This should fail, because the "a" and "b" labels are not provided!
    processed_input_messages.set_function(lambda: 1)
```

In general, it would be important to check, for every metric type, if all the labels are set when calling `.set()`, `.inc()`, `.set_function()`, and the other similar metrics.

### Additional contract requirements

- For a metric configured with label names but called without label values, these operations must raise `ValueError` with a message containing `missing label values`:
  - `Counter.inc()` and `Counter.count_exceptions()` (including use of the returned decorator without label values).
  - `Gauge.inc()`, `Gauge.dec()`, `Gauge.set()`, `Gauge.set_function()`, `Gauge.track_inprogress()`, and `Gauge.time()`.
  - `Summary.observe()` and `Summary.time()`.
  - `Histogram.observe()`.
