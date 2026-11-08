Odd formatting decision with parenthesized function call with attrset
## Input
```nix
{
  nixpkgs-fmt = (buildCargoCrate {
    name = "nixpkgs-fmt";
    # TODO: probably want to filter .gitignore or something
    src = sources.nixpkgs-fmt;
  }).nixpkgs-fmt.build;
}
```

## Output
```nix
{
  nixpkgs-fmt = (buildCargoCrate {
    name = "nixpkgs-fmt";
    # TODO: probably want to filter .gitignore or something
    src = sources.nixpkgs-fmt;
  }
  ).nixpkgs-fmt.build;
}
```

## Desired output

I personally find the original less odd-looking here, and this seems to be one of the few cases where I disagree with nixpkgs-fmt's decision. Sorry if this has already been opened/discussed; I couldn't find anything from a brief search of the issue tracker.
