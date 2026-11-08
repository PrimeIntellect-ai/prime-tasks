Allow `script` to be a single string value
Currently, this is invalid:
```yaml
aliases:
  foo:
    image: xyz
    script: echo Hello
```

### Additional contract requirements

A mapping-form alias whose `script` value is a string must be accepted and interpreted as one script command.
