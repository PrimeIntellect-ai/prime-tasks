sample: missing space after inherit
In some cases when using `inherit` there is no white space inserted after the `;`  to separate the next element.

## Input
```nix
let
  a = {
    inherit foo; inherit bar;
  };
  b = {
    inherit foo; # Comment
  };
  c = {
    inherit foo; bar = baz;
  };
in
{ }

```

## Output
```nix
let
  a = {
    inherit foo;inherit bar;
  };
  b = {
    inherit foo;# Comment
  };
  c = {
    inherit foo; bar = baz;
  };
in
{ }

```

## Desired output

```nix
let
  a = {
    inherit foo; inherit bar;
  };
  b = {
    inherit foo; # Comment
  };
  c = {
    inherit foo; bar = baz;
  };
in
{ }

```
