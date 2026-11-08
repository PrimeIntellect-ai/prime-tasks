Variables in object binding pattern
jq allows to bind object value by using variable in object keys.
```sh
❯ jq -c '. as {$a:[$b]} | {$a,$b}' <<< '{"a":[1]}'
{"a":[1],"b":1}

❯ xq -c '. as {$a:[$b]} | {$a,$b}' <<< '{"a":[1]}'
Error: compile query

Caused by:
    CompileError(UnknownVariable(Identifier("a")))

❯ xq --version
xq 0.1.9-95558180fabd53143a91d72e226780939461f8c5
```
