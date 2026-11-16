sample: multi-line parenthesis
When a parenthesis is multi-line it should indent the inner bits.

## Input
```nix
{
  xxx = listToAttrs (
  concatMap (name:
    let a = 4; in 5
));
}
```

## Output
```nix
{
  xxx = listToAttrs (
  concatMap (name:
    let a = 4; in 5
  ));
}

```

## Desired output

```nix
{
  xxx = listToAttrs (
    concatMap (name:
      let a = 4; in 5
    )
  );
}

```
