[bug] raising ConanInvalidConfiguration from pre_validate hook propagates exception
### Describe the bug

With a hook like this:
```
def pre_validate(conanfile):
    if some_condition_external_to_the_recipe:
        raise ConanInvalidConfiguration("Raised from pre_validate")
```

The expectation is that this behaves _as if_ exception was raised from within the `validate()` method.
Instead, the exception is propagated all the way to the top


The problem is here:
https://github.com/conan-io/conan/blob/cc258fb079f5c7449d72d74f64156d61b73d6546/conans/client/graph/compute_pid.py#L74-L85

[HIDDEN]


### How to reproduce it

_No response_

### Additional contract requirements

When either `pre_validate` or `post_validate` raises `ConanInvalidConfiguration`, the operation must report a validation configuration error rather than an unhandled top-level exception.
