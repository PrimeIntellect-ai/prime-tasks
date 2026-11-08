Registering a metric after creating RestrictedRegistry with its name does not add the metric to RestrictedRegistry
The method `restricted_registry` works by filtering all metrics once at the time of its creation, as one can see from looking at the file `registry.py`.

If you register a metric after creating the restriction for it, it is not added to the restricted registry - while the docstring could be interpreted as claiming otherwise.

Solution 1: the class could be documented in a way that makes its behaviour explicit;
[HIDDEN]

### Additional contract requirements

A restricted registry is a live view of its parent registry. Each call to `collect()` reflects metrics currently registered in the parent, including matching metrics registered after the restricted registry was created. Collection yields only samples with names selected when the restriction was created.
