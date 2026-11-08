Improve `convert_index_to_field` rule to refactor table entries
Basically, improve the rule to convert:
```lua
local t = {
    ["name"] = true
}
```
Into:
```lua
local t = {
    name = true
}
```
