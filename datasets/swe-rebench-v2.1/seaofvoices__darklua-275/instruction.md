`remove_unused_variable` incorrect behavior
`remove_unused_variable` incorrectly removes unassigned local variables in grouped local assignments after a function call and assigned variable.

# Reproduction
`a.luau`:
```lua
local c = 0;
(function()
    local a, b, c = (function()end)(), 0;
    c = 1;
end)();
assert(c == 0);
```

`.darklua.json`:
```json
{
    "rules": [
        "remove_unused_variable"
    ]
}
```

```
darklua process a.luau out.luau --verbose
 INFO > using configuration file `.darklua.json`
 INFO > successfully processed `a.luau`
 INFO > executed work in 1.2508ms
successfully processed 1 file (in 2.049ms)
```
```
darklua --version
darklua 0.13.1
```

`out.luau`:
```lua
local c = 0;
(function()
local a=(function()end)();
    c = 1;
end)();
assert(c == 0);
```
This output is incorrect. When combined with `group_local_assignment` and `rename_variables`, this bug is more likely to break scripts.

### Additional contract requirements

- For `local a, b = true b = false`, the output must be exactly `local b = nil b = false`.
- For `local a, b, c = call() b = false`, the output must be exactly `local a, b = call() b = false`.
- For `local a, b, c = true b = false`, the output must be exactly `local b = nil b = false`.
