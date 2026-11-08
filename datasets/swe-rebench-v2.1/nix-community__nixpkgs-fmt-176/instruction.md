sample: if statement after key
## Input
```nix
{
  userHome = if home != null
    then home
    else config.users.extraUsers.${user}.home;
}
```

## Output
```nix
{
  userHome = if home != null
  then home
  else config.users.extraUsers.${user}.home;
}

```

## Desired output

```nix
{
  userHome = if home != null
    then home
    else config.users.extraUsers.${user}.home;
}
```
or maybe
```nix
{
  userHome =
    if home != null
    then home
    else config.users.extraUsers.${user}.home;
}
```

### Additional contract requirements

When an `if ... then ... else` expression spans multiple lines, the required output is
the second layout shown above: the assignment is broken before `if`, and `if`, `then`,
and `else` each start their own line, indented one level relative to the key. The first
layout shown above is not part of the required output.
