sample: indented let body
whenever a let..in block is being added, it re-indents the whole body, creating a lot of noise in the diff.

Maybe it's worth special-casing at least for the top-level to not indent the body?

## Input
```nix
{ stdenv, fetchFromGitHub }:
let
pname = "hello";
version = "1.2.3";
in
stdenv.mkDerivation {
  inherit pname version;
  src = fetchFromGitHub {
    owner = "xxx";
    repo = pname;
    rev = version;
    sha256 = "...";
  };
}
```

## Output
```nix
{ stdenv, fetchFromGitHub }:
let
  pname = "hello";
  version = "1.2.3";
in
  stdenv.mkDerivation {
    inherit pname version;
    src = fetchFromGitHub {
      owner = "xxx";
      repo = pname;
      rev = version;
      sha256 = "...";
    };
  }

```

## Desired output

```nix
{ stdenv, fetchFromGitHub }:
let
  pname = "hello";
  version = "1.2.3";
in
stdenv.mkDerivation {
  inherit pname version;
  src = fetchFromGitHub {
    owner = "xxx";
    repo = pname;
    rev = version;
    sha256 = "...";
  };
}
```
