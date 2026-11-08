Inconsistent Behavior of [] between version 1.7.0 and 1.8.3
Consider the following input:
```
{
  "singleArray": [{"foo":"bar"}]
}
```
and JSONata expression:
`singleArray[]`

In version 1.7.0, the evaluated result is
```
[
  {
    "foo": "bar"
  }
]
```
but in 1.8.3 it is
```
[
  [
    {
      "foo": "bar"
    }
  ]
]
```
Which evaluation is correct and why?

### Additional contract requirements

For `singleArray[]`, the correct result is the flat singleton array containing the object, not an array nested inside another array. The `[]` path step expands the input array into its members; a singleton sequence produced this way remains one member and must not gain an extra array wrapper. This behavior applies regardless of the member's property values, not only to the example shown above.
