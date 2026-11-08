Template does not support adding items to array
Here is my template
```
#set($foo = [])
#set($ignore = $foo.add('bar'))
$foo
```

The expected output is `[bar]` but it is not so. The engine ignores the add method and prints an empty array `[]`

### Additional contract requirements

- `$foo.add(value)` adds `value` to the array `$foo` only when `$foo` does not already define its own `add` method. If `$foo` already defines an `add` method, that method is called with `value` and its result is used.


- For example, adding `{'foo':'bar'}` to an empty array and rendering it must produce `[{foo=bar}]`.
