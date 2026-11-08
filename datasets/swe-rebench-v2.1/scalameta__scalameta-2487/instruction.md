Cannot format scala3 macro quote block if there are white-space after `'`
Cannot format scala3 macro quote block if there are white-space between `'` and `{`

For example

```scala
'  {
xxx
}
```
will complain `error: unclosed character literal`
