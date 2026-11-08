Enum values should be objects
Given:

```JS
enum Things {
    "foo",
    "bar"
};
```

Enum values current result in,

```js
[
  {
    "type": "ws",
    "value": "\n          "
  },
  "foo",
  {
    "type": ","
  },
  {
    "type": "ws",
    "value": "\n          "
  },
  "bar",
  {
    "type": "ws",
    "value": "\n        "
  }
]
```

This switching of types makes things really inconsistent. Would have expected an Object like:

```js
  {
    "type": "enum-value",
    "value": "foo",
  }
```

And maybe, for compat:

```js
  {
    "type": "enum-value",
    "value": "foo",
    toString(){
       return this.value;
    }
  }
```

### Additional contract requirements

- Each enum value object must have `type` equal to `"string"` and a `value` field containing the enum value.
