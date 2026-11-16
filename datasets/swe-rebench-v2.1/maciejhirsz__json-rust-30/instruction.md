Using Strings as index
Right now it's kind of verbose to do this:

``` rust
let j_test = object!{
    "hi" => 123,
    "na" => 345
};
let mut j_test2 = json::JsonValue::new_object();
for (key, val) in j_test.entries() {
    j_test2["subsub"][key] = val.as_u32().into();
}
```

Error:
``` rust
trait bound `json::JsonValue: std::ops::Index<&std::string::String>` is not satisfied
```

You have to write
``` rust
j_test2["subsub"][&**key] = val.as_u32().into();
```

And if you use ref you have to write:

``` rust
for (ref key, ref val) in j_test.entries() {
    j_test2["subsub"][&***key] = val.as_u32().into();
}
```

As an idea for improvements.

### Additional contract requirements

- A `JsonValue` can be read-indexed by an owned `String`, returning the value stored under that key, so that `json_value["key".to_string()]` yields the same value as `json_value["key"]`.
- A `JsonValue` can be read-indexed by a borrowed `&String`, returning the value stored under that key, so that `json_value[&key]` (where `key: String`) yields the same value as `json_value["key"]`.
- A `JsonValue` can be mutably indexed by an owned `String`, returning a mutable reference to the value stored under that key, so that `json_value["key".to_string()] = new_val.into()` assigns to that key.
- A `JsonValue` can be mutably indexed by a borrowed `&String`, returning a mutable reference to the value stored under that key, so that `json_value[&key] = new_val.into()` (where `key: String`) assigns to that key.
