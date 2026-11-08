sample: function body indent
I think the function body shouldn't be indented if the arguments are on the same level.

## Input
```nix
let
  aaa =
 {foo,bar}:
              foo+bar
;
bbb = {foo,bar}:
              foo+bar
;
in
  null
```

## Output
```nix
let
  aaa =
    { foo, bar }:
      foo + bar
  ;
  bbb = { foo, bar }:
    foo + bar
  ;
in
null

```

## Desired output

```nix
let
  aaa =
    { foo, bar }:
    foo + bar
    ;
  bbb = { foo, bar }:
    foo + bar
    ;
in
null
```
