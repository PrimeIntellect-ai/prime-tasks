allowParamsAnywhere named parameters
Hello,

it would be awesome if instead of the order of the parameter declared as an integer, the named parameter could be used.

So for example in
```
function: 'json_decode()'
message: ''
allowParamsAnywhere:
    4: ::JSON_THROW_ON_ERROR
```
instead of `4`, `flags` could be used, so that we don't need to define all the ommited parameters before `flags`.

### Additional contract requirements

Named parameters are supported in the `allowParams*` configuration keys, not only in `allowParamsAnywhere`. A parameter may be identified by its name instead of its integer position, including when matching a configured value.

A parameter can be configured either as a single entry keyed by its position (an integer) or by its name (a string), or as an array with a `position` key (integer) and a `name` key (string). Value-matching keys (`allowParamsAnywhere`, `allowParamsInAllowed`) also take a `value` key; any-value keys (`allowParamsAnywhereAnyValue`, `allowParamsInAllowedAnyValue`) do not. For any-value keys a parameter may also be given as a bare integer position or a bare string name. For example, the `json_decode()` example above can be written as:

```neon
allowParamsAnywhere:
    -
        position: 4
        name: 'flags'
        value: ::JSON_THROW_ON_ERROR
```

A call that passes the parameter by name (for example `json_decode($json, flags: JSON_THROW_ON_ERROR)`) matches the rule even when the preceding positional parameters are omitted.
