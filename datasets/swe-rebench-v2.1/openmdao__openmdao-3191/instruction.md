Give the user explicit access to the subproblem in SubmodelComp.
### Desired capability or behavior.

Currently the sub-problem of the SubModelComp is underscored, implying that it is "private."

Certain actions by the user require access to the sub-problem: debugging, adjusting driver/solver attributes, etc.
To enable this, we will add a `@property` to SubModelComp: `problem`.

[HIDDEN]

### Associated POEM

None

### Additional contract requirements

- Reading `SubmodelComp.problem` returns the component’s sub-problem.
- The property is read-only; attempting to assign to it raises `AttributeError`.
