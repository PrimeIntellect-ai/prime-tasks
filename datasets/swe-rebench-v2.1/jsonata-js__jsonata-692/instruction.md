JSONata leaks internal references in expression when using lambdas
I am creating this after corresponding with @andrew-coleman over email as it has some security implications.

Currently, one can use lambdas as a way to grab references to JSONata internals. For example:

```
$leak_env_refs := function() {1};
$leak_env_refs.environment.bind('whatever_you_want', false);
```

This seems unintentional and can potentially be used maliciously.

### Additional contract requirements

- Accessing a lambda's `environment` must evaluate to `undefined`; for example, `( $f := function(){1}; $f.environment )` must return `undefined`.
