.remove  and .clear not working with multiprocessing mode
Trying to remove a given set of labels for a metric doesn't work.
The label value is still readable by the collector after it's presumed removal ?
any suggestions ?

### Additional contract requirements

- Metric objects such as `prometheus_client.core.Counter` expose `remove(*labelvalues)` and `clear()`.
- `remove(*labelvalues)` deletes the labelled instance identified by the given label values. A metric created without any label names raises `ValueError` when `remove` is called.
- `clear()` removes every labelled instance of the metric.
- When the environment variable `PROMETHEUS_MULTIPROC_DIR` or its lowercase variant `prometheus_multiproc_dir` is set, both `remove` and `clear` emit a `UserWarning` stating that the operation is not implemented in multi-process mode, and the values reported by the multi-process collector are left unchanged.
