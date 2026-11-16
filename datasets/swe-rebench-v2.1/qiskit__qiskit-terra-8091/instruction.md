Number of experiments in primitive results
### What should we add?

In the current specification of `SamplerResult` and `EstimatorResult` there is no unified way of retrieving the the total number of experiments that are comprised within one result object. It would be great to add a property `result.num_experiments` that would retrieve it.

Additionally, when one of these objects is instantiated, no checks are performed to verify that the number of experiments is consistent across all data fields. This should be performed as well.

### Additional contract requirements

- The module `qiskit.primitives.base_result` provides a public class `BasePrimitiveResult` that supplies the behaviour below to inheriting result dataclasses.
- `SamplerResult` and `EstimatorResult` provide this behaviour.
- `num_experiments` is a property that returns the number of experiments represented by the result, i.e. the common length of its data fields.
- `experiments` is a property that returns a tuple with one dictionary per experiment; each dictionary maps every data field name to that experiment's value.
- `decompose()` is a method that returns an iterator over results of the same concrete class, one per experiment, where each data field holds a one-element tuple containing that experiment's value.
- When a result is instantiated, every data field must be a sequence or a `numpy.ndarray`, excluding `str` and `bytes`; otherwise a `TypeError` is raised. All data fields must have the same length; otherwise a `ValueError` is raised.
