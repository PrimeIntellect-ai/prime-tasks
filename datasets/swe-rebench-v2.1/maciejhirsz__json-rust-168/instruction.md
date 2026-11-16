Fails to correctly parse key with escaped forward slash
When attempting to parse the following string:

```
{"a\/b":"c\"d\"e","f":1}
```

The following value is created:

```
{
  "a/b": null,
  "c\"d": "c\"d\"e",
  "f": 1
}
```

It seems the combination of the escaped forward slash and the escaped quote in the value causes the parser to fail to attach the value in the correct location.
