Make FileFormats.MPS.Model an AbstractOptimizer
@mlubin asks:

![image](https://github.com/jump-dev/MathOptInterface.jl/assets/8177701/e72b3093-a062-48cc-bc01-0e7f2ca7a873)

The other approach is to do what AmplNLWriter does an wrap the model in an optimizer:

https://github.com/jump-dev/AmplNLWriter.jl/blob/4e1edda22d272e3df27893eee7a7ca1e2da19ac9/src/AmplNLWriter.jl#L79-L80

### Additional contract requirements

Although the issue title asks to make `MOI.FileFormats.MPS.Model` an
`MOI.AbstractOptimizer`, the accepted solution instead validates the model
backend in `optimize!`. `MOI.FileFormats.MPS.Model` is a `MOI.ModelLike` but is
**not** an `MOI.AbstractOptimizer`, and the fix must not require it to be one.
JuMP must accept any `MOI.ModelLike` as a model backend and, when `optimize!` is
called with a backend that is not an `MOI.AbstractOptimizer`, throw the
`ErrorException` described in the interface.

When a model's backend does not provide a solver name, the model's display must
report `Solver name: unknown`.

The MPS model serializes to the MPS format, which begins with `NAME` and ends
with `ENDATA`.


- The MPS serialization must end with `ENDATA` followed by a newline.
