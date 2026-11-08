join() of array with nulls throws NullPointerException
As mentioned in https://github.com/OpenRefine/OpenRefine/issues/6521#issuecomment-2104513492

### To Reproduce
Steps to reproduce the behavior:
1. `parseJson("['a',null,'b']".join(',')`

### Current Results
NullPointerException

### Expected Behavior
`"a,,b"` (but because of a different bug it should currently return `"a,b"`

### Additional contract requirements

For the reported array containing a null between `a` and `b`, joining with `,` completes without an exception and produces `a,b`. The null element contributes no text and does not add a separator.
