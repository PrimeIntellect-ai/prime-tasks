Object transform operator allows arrays in its update expression
The object transform operator has the following syntax:

```
root ~> | location | update [, delete] |
```

where `update` is an object that gets merged into the root object. All of the examples I've seen use a JSON object for the `update` part. But it also seems to work with an array, e.g.

```
{} ~> |$|["one", "two", "three"]|
```

evaluates to:

```
{
  "0": "one",
  "1": "two",
  "2": "three"
}
```

Shouldn't this be an error? There is a [type check](https://github.com/jsonata-js/jsonata/blob/master/src/jsonata.js#L2557) in the code but it doesn't catch this case because JavaScript objects and arrays both have type "object".
