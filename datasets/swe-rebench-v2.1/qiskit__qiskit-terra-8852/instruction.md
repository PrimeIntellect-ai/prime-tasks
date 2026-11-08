Add support for variable width operations to Target
### What should we add?

Right now the target class doesn't have proper support for modelling instructions that have variable width. If you have a gate that can use more than a single number of qubits and the backend supports all variants of that instruction (or at least more than one). We don't have a way to express that. The target currently requires a 1:1 mapping of operation name to a `Operation` instance and that instance is used for type checking and parameter checking at different points in the transpiler. However this requirement won't work for variable width instructions because a single instance of the instructions can only have a single number of qubits.

To be able to accurately model these instructions being supported on a target backend we need to come up with an interface to model this in the target, which might mean introducing a `TargetV2`.

### Additional contract requirements

The `Target` introspection properties must expose globally-defined
variable-width operations (those registered by passing a class to
`Target.add_instruction`) as follows:

- `Target.instructions` returns a list of `(operation, qargs)` tuples. For a
  globally-defined operation the `qargs` element is `None`. For an operation
  registered by class the `operation` element is the class itself (for example
  `(IfElseOp, None)`); for an operation registered by instance the `operation`
  element is that instance.
- `Target.operations` contains the class for each globally-defined operation.
- `Target.operation_names` contains the lookup name supplied for each
  globally-defined operation.
- `Target.qargs` is `None` when the target contains an operation registered
  without explicit qargs (for example an instance added with no properties);
  otherwise it is the set of qargs of the operations registered with explicit
  qargs.
- `Target.qargs_for_operation_name(name)` returns `None` for a globally-defined
  operation.
- `Target.instruction_supported` recognizes a globally registered operation for
  qargs of any width when all qubit indices are within the target's range, and
  does not recognize it when a qarg is outside that range.
