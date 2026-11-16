Get placeholder error on del/1 function
```sh
❯ jq -n '{x:[1]} | del(.x[0],.x)'
{}

❯ xq -n '{x:[1]} | del(.x[0],.x)'
Error: IndexOnNonIndexable("placeholder")
```
