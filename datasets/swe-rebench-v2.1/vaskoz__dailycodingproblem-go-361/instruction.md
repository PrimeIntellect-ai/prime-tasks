Day 173
Good morning! Here's your coding interview problem for today.

This problem was asked by Stripe.

Write a function to flatten a nested dictionary. Namespace the keys with a period.

For example, given the following dictionary:
```
{
    "key": 3,
    "foo": {
        "a": 5,
        "bar": {
            "baz": 8
        }
    }
}
```
it should become:
```
{
    "key": 3,
    "foo.a": 5,
    "foo.bar.baz": 8
}
```

### Additional contract requirements

- Provide the Go function `FlattenMap(m map[string]interface{}) map[string]interface{}`.
