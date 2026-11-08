sample: `++` folding
nixpkgs-fmt should respect `\n` and never fold lines back into one

## Input
```nix
foo ++
bar
```

## Output
```nix
foo ++ bar

```

## Desired output

```nix
foo
++ bar
```

### Additional contract requirements

- For the tested braced assignment case, format the wrapped concatenation with this indentation:
```nix
{
  a = "foo"
  ++ "bar"
  ++ "lol"
  ++ "bla"
  ;
}
```
- For the nested `buildInputs` concatenation, format the continuation as shown:
```nix
pkgs.example rec {
  buildInputs = [ pkgs.foo ]
  ++ pkgs.stdenv.lib.optionals pkgs.stdenv.isDarwin [
    pkgs.bar
  ];
}
```
