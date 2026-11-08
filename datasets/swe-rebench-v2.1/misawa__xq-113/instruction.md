flatten/1 on empty array emits null instead of []
The flatten filter on empty array should emit an empty array.
```sh
❯ jq -n '[] | flatten(0)'
[]

❯ xq -n '[] | flatten(0)'
null

❯ xq --version
xq 0.2.10-ad33a92d252fc4842f10730973e16f5da8434035
```
