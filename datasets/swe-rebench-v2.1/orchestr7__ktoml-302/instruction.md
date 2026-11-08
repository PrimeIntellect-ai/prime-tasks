Support Arrays of Tables
I see this is already called out as a feature that's not yet implemented in the README:

> ❌ Array of Tables

I just wanted to make a ticket for it so folks can vote for it, and so I can get notified when it's implemented.  (It's currently a blocker for my use case.)

---

My use case is this:

I want to support multiple configuration environments in one file. Like:

```toml
[[environments]]
name = "foo"
# …

[[environments]]
name = "bar"
# …
```

But that currently gives an error:

> Not able to parse the key: [[environments]] as it contains invalid symbols. In case you would like to use special symbols - use quotes as it is required by TOML standard: "My key ~ with special % symbols"

---

Alternatively, I also tried a "Map of Tables" approach like this, but that didn't work either:

```toml
[environments.foo]
# …

[environments.bar]
# …
```

Error:
>  Invalid number of key-value arguments provided in the input for deserialization. Missing the required field <0> from class <kotlin.collections.LinkedHashMap> in the input
