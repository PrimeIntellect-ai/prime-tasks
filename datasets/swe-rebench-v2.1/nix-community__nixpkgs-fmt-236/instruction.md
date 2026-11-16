sample: Indenting all but the first line is a bit too much.
I tried using `nixpkgs-fmt` on a test I was working on and it indented everything except for the first line an extra level, which seemed kind of ridiculous in the case of `nixos/tests/ceph-*.nix`. Below is a smaller example showing the same behavior, though to a much smaller extent since there are fewer lines for it to indent.

## Input
```nix
import ./make-test-python.nix ({pkgs, lib, ...}:

let
  foo = 42;
  bar = 57;
in {
  baz = qux;
})
```

## Output
```nix
import ./make-test-python.nix ({ pkgs, lib, ... }:

  let
    foo = 42;
    bar = 57;
  in
  {
    baz = qux;
  })

```

## Desired output

```nix
import ./make-test-python.nix ({pkgs, lib, ...}:

let
  foo = 42;
  bar = 57;
in {
  baz = qux;
})
```

### Additional contract requirements

- For the analogous import/lambda expression whose `let` contains only `bar = 57;`, format `in` and `{` on separate lines (`in\n{`).
