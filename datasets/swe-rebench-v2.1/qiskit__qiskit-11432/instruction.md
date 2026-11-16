Support binding/assigning parameters by name
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues to confirm this idea does not exist. -->

### What is the expected enhancement?

From @Cryoris 's comment in https://github.com/Qiskit/qiskit-terra/issues/5557#issuecomment-757520462 :

> Personally I'd be fine if that'd work with a string as well, since parameter names are unique in circuits.
> ```
> partially_bound = circuit.assign_parameters({'x': value})
> ```

We should consider adding support for binding and assigning parameters via their string name. This was originally omitted for concerns over overlapping parameter names between different circuits. However, by the stage of `bind_`/`assign_`, the `Parameter` s on a given circuit are fixed and guaranteed to be unique, so there isn't really a possibility for the ambiguity that exists when composing two parameterized circuits.
