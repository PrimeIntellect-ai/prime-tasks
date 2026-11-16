"empty" array values erroring starting with v14.0.0
I checked the changelog, but I couldn't find a match for this behaviour. I have a script on our CI server that evaluates to `--tag --tag smoke` sometimes based on the existence of a env var or not. Essentially `--tag $TAG1 --tag $TAG2`.

This worked as expected in v13.1.1, but started failing in v14.0.0 and v15.0.0 with:

```
Invalid values:
  Argument: tag, Given: , Choices: ...
```

### Additional contract requirements

- When an array-typed option is given with no value (for example `--tag` immediately followed by another option, or at the end of the arguments), the option's configured default value is used. If that default is an array, it is used as the option's value directly; if it is a primitive value, it is used as a single-element array.
