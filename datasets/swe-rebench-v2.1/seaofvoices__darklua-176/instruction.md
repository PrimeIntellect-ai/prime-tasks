`remove_compound_assignment` copying comments/newlines in between statements
### How to replicate:

1. Go to https://darklua.com/try-it/
2. Use the following rule below:
```json5
{
  rules: [
    'remove_compound_assignment',
  ],
}
```
### Results:

<table>
<tr>
<th>Input</th>
<th>Output</th>
<th>Expected</th>
</tr>
<tr>
<td valign="top">

```lua
local x = 0
x += 1-- this is ok

local y = 0
print(y)
y += 1-- this is ok


local y = 0

y += 1-- one newline appears

local z = 0
--duplicate
z += 1--it copies the comments

local a = 0
--copies
--all
--comments

--in between
a += 1
```

</td>
<td valign="top">

```lua
local x = 0
x =x +1-- this is ok

local y = 0
print(y)
y =y +1-- this is ok


local y = 0

y =
y +1-- one newline appears

local z = 0
--duplicate
z =--duplicate
z +1--it copies the comments

local a = 0
--copies
--all
--comments

--in between
a =--copies
--all
--comments

--in between
a +1
```

</td>
<td valign="top">

```lua
local x = 0
x =x +1-- this is ok

local y = 0
print(y)
y =y +1-- this is ok


local y = 0

y =y +1-- one newline appears

local z = 0
--duplicate
z =z +1--it copies the comments

local a = 0
--copies
--all
--comments

--in between
a =a +1
```

</td>
</tr>
</table>
