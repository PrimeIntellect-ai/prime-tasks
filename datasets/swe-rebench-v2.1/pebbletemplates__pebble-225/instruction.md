Can not concatenate SafeString
In Pebble 1.x I used to be able to concatenate the output of a macro with the output of another macro.  Something like:

```twig
{{ macro1() + macro2() }}
```

In Pebble 2.x I can no longer do that and I think the problem is [this](https://github.com/PebbleTemplates/pebble/blob/master/src/main/java/com/mitchellbosecke/pebble/utils/OperatorUtils.java#L39-L46) hunk of code [HIDDEN]

### Additional contract requirements

- Macro outputs must be concatenable with the `+` operator, including when those outputs are `SafeString` values.
