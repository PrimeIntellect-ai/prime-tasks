Support const keyword in generator
**What would you like to be added**:
Currently the const word is ignored

**Why is this needed**:
To distinghish, in CallTask, the right class when there is no param.

### Additional contract requirements

- Generated models must honor schema `const` values when determining a call definition's concrete type.
- When a `CallTask` calls a function with no parameters, its generated model must resolve to the `CallFunction` concrete type.
