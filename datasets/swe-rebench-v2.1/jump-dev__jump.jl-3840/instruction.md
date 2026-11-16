String valued MOI attributes: Improved error messages or `AbstractString` instead of `String`?
The following code produces an error that I thought could be worth pointing out, since I assume it could be either

- caught somewhere in a "fallback" to produce a hint towards the actual mistake, or
- [HIDDEN]

However I didn't manage to find the actual location where the `value` in some `MOI.set(...)` function is typed as `String`, and I'm unsure if there are other attributes where allowing to pass an `AbstractString` would negatively influence something.

It took me embarrassingly long to get that this was just caused by the `SubString` that made it's way into the model name, because I got fooled by the error and stacktrace ...

### Code

```julia
using JuMP

model_name = split("foo.bar", ".")[1]

model = Model()
set_attribute(model, MOI.Name(), model_name)          # error
set_attribute(model, MOI.Name(), string(model_name))  # works
```

### Error message

```console
ERROR: MathOptInterface.SetAttributeNotAllowed{MathOptInterface.Name}: Setting attribute MathOptInterface.Name()
cannot be performed. You may want to use a `CachingOptimizer` in `AUTOMATIC` mode or you may need to call
`reset_optimizer` before doing this operation if the `CachingOptimizer` is in `MANUAL` mode.
```

### Additional contract requirements

When a string-valued MOI attribute is set with an `AbstractString` value such as a `SubString`, the operation should either succeed with the expected string value or report a useful diagnostic. It must not fail with the misleading `SetAttributeNotAllowed` error shown above.
