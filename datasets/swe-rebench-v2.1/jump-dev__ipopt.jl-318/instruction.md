add `MathOptInterface.Name()` attribute
When using Ipopt and ParametricOptInterface in direct mode this error happens:

```Julia
julia> model = direct_model(POI.Optimizer(Ipopt.Optimizer()))
Error showing value of type Model:
ERROR: MathOptInterface.GetAttributeNotAllowed{MathOptInterface.Name}: Getting attribute MathOptInterface.Name() cannot be performed: Ipopt.Optimizer does not support getting the attribute MathOptInterface.Name(). You may want to use a `CachingOptimizer` in `AUTOMATIC` mode or you may need to call `reset_optimizer` before doing this operation if the `CachingOptimizer` is in `MANUAL` mode.
```
