Add functions thats subtracts a field from another field
See openaddresses/openaddresses#2195

Here's a example data that's motivating this:

```
{
  "addrnum": "400 E",
  "unitid": "E",
  "fulladdr": "400 E EMERY AVE"
}
```

In this case it's very difficult if not impossible to write a `regexp` function that would know the difference between a unit `E` and an `E` that's an address pre-directional.   That is, without awareness of other fields values, it's not possible to know if the street value shoud be `E EMERY AVE` or `EMERY AVE`.  The data motivating this also has a wide variety of unit formats:

* `[0-9]+`
* `[A-Z]`
* `[A-Z]-?[0-9]+`
* `[0-9]+[A-Z]`
* `BLDG [0-9]+`
* a variety of one-off values that can't be captured by regexes easily

These conform function would look something like:

```
{
  "number": {
    "function": "remove_postfix",
    "field": "addrnum",
    "field_to_remove": "unitid",
  },
  "street": {
    "function": "remove_prefix",
    "field": "fulladdr",
    "field_to_remove": "addrnum"
  },
  "unit": "unitid"
}
```

The result of these functions would be:

```
{
  "number": "400",
  "street": "EMERY AVE",
  "unit": "E"
}
```

In a larger context, there are some sources that have `number` identified as a distinct field but the `street` value can only be derived using a `regexp`.  In these cases, the `regexp` function can be replaced with `remove_prefix`.
