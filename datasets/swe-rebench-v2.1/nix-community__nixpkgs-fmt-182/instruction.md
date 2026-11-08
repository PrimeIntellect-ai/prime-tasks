Parenthese after square brackets should stay on the same line

## Input
```nix
{ python3 }:
python3.pkgs.buildPythonApplication {
  propagatedBuildInputs = (with python3.pkgs; [
    pkg1
  ]);
}

```

## Output
```nix
{ python3 }:
python3.pkgs.buildPythonApplication {
  propagatedBuildInputs = (with python3.pkgs; [
    pkg1
  ]
  );
}
```

## Desired output

```nix
{ python3 }:
python3.pkgs.buildPythonApplication {
  propagatedBuildInputs = (with python3.pkgs; [
    pkg1
  ]);
}
```
