Application of 'remove_types' can change runtime behavior where a function call has a type assertion
Adding a type assertion to a function call has the (runtime) effect of truncating any returned values to a maximum of one value:
```Lua
local function multipleReturns()
    return 1, 2
end
print(multipleReturns() :: any)
```
This will output "1".

Currently, the 'remove_types' rule translates line 4 as:
```Lua
print(multipleReturns())
```
This will output both "1" and "2", incorrectly.

The 'remove_types' rule should wrap these type-asserted calls in parentheses:
```Lua
print((multipleReturns()))
```
This will output "1", correctly.

### Additional contract requirements

- When removing a type assertion from variadic arguments, `return ... :: any` must produce `return (...)`.
- Removing a type assertion from `return value :: any` must produce `return value`, and removing one from `return {} :: any` must produce `return {}`.
