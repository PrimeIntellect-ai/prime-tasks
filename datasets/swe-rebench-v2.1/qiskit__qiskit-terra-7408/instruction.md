`QuantumCircuit._check_dup_param_spec` becomes slow for many gates reusing few parameters
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues to confirm this idea does not exist. -->

### What is the expected enhancement?

When building a parameterized circuit where a large number of gates re-use a comparatively small number of parameters, `QuantumCircuit._check_dup_param_spec` becomes a performance bottleneck.

For example, `circuit_construction.ParameterizedCircuitConstructionBench.time_build_parameterized_circuit` takes 90s to build a 131k gate circuit with 8 distinct parameters, vs. <5s to build a 131k gate circuit with anything more than 128 parameters:

https://qiskit.github.io/qiskit/#circuit_construction.ParameterizedCircuitConstructionBench.time_build_parameterized_circuit?x-axis=number%20of%20params

[HIDDEN]

### Additional contract requirements

- Building a parameterized circuit with many gates that reuse a small number of parameters must scale roughly linearly with the number of gates, not quadratically. Concretely, constructing a circuit with four times as many gates (reusing the same small set of parameters) must not take more than eight times as long.
