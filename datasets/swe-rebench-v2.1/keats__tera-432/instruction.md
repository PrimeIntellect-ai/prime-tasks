Variable keys with forward slashes
I've got a hashmap with keys that contain slashes. I can see the context set as expected:

```
&context = Context {
    data: {
        "variables": Object(
            {
                "Test/Variable": String(
                    "test value",
                ),
            },
        ),
    },
}
```

But I can't seem to access the value using either `variables["Test/Variable"]` or `variables['Test/Variable']`. I couldn't find a test that covers this, and it's not explicitly mentioned in the documentation, but I assumed that the bracket-notation could be used specifically for this use case.

The returned error is:

> Variable `variables[\'Test/Variable\']` not found in context while rendering \'tpl\': the evaluated version was `variables.Test/Variable`. Maybe the index is out of bounds?

[HIDDEN]

I feel like this just isn't possible. Should it be? Since it accepts a hashmap, and the context contains the data, it should be able to fetch the data even if the variable contains slashes.

I don't have control of the keys in the context, but I can of course do some pre-processing to convert them into variables that work with the dot-notation, but I was hoping this is (or can be) supported in Tera by default.

### Additional contract requirements

- A template must be able to retrieve a map value whose key contains a forward slash using either single-quoted or double-quoted bracket notation; the expression should return the value stored under that key.
