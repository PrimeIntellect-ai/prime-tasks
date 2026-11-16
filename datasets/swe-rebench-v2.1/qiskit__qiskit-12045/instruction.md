ParameterVector support for Schedules
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues to confirm this idea does not exist. -->

### What is the expected enhancement?

Currently, `QuantumCircuit`s support `assign_parameters` with `ParameterVector` input. The task is to add support similarly for `Schedule`s, which now support parameter assignment as well.

### Additional contract requirements

For both `Schedule` and `ScheduleBlock`, assigning a `ParameterVector` binds each vector element to its corresponding supplied value, including when a value is another parameter expression. The supplied value must be a sequence with exactly one value per vector element; otherwise the assignment is rejected with `PulseError`. When `inplace=True`, vector assignment mutates and returns the same schedule object.
