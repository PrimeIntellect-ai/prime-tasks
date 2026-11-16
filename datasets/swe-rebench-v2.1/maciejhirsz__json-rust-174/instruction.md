is_u32 returns true for floats
```json
{
    "entity_number": 57,
    "name": "fast-splitter",
    "position": {
        "x": -5.5,
        "y": 4
    },
    "direction": 4
}
```
In this example, `obj["position"]["x"].as_i32().unwrap() == -55`

Floats should return `false` for the `is_<integer>` functions.
