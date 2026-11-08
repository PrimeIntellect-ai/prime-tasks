GlobalsHelperFn type validation crashes for list types or validation functions
### Problem statement
The `*Globals` classes defined in https://github.com/cloudtools/troposphere/blob/main/troposphere/serverless.py have some properties with their type specified as `[T]` or as validation functions (e.g. validate_memory_size). They all inherit from [GlobalsHelperFn](https://github.com/cloudtools/troposphere/blob/main/troposphere/serverless.py#L659) which does not handle those types during runtime type validation, all it does is feed them into `isinstance` which ends up throwing:
```
TypeError: isinstance() arg 2 must be a type or tuple of types
```

### Steps to reproduce
```py
from troposphere.serverless import FunctionGlobals
FunctionGlobals(MemorySize=3072)
```

---

I've noticed [BaseAWSObject](https://github.com/cloudtools/troposphere/blob/main/troposphere/__init__.py#L141) has proper handling for such types [here for validation functions](https://github.com/cloudtools/troposphere/blob/main/troposphere/__init__.py#L257) and [here for lists](https://github.com/cloudtools/troposphere/blob/main/troposphere/__init__.py#L270). Something similar needs to be used for the Globals.
