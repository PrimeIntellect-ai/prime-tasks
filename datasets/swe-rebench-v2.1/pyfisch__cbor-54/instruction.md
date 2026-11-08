Override `is_human_readable`
According to the docs when [`is_human_readable`](https://docs.rs/serde/1.0.23/serde/trait.Serializer.html#method.is_human_readable) is `false` serializer can produce more compact and efficient form. I think this is what expected from cbor serializer. (default is `true`)

Unfortunately changing it is a breaking change, but I think it's okay in zero-point release.

So I'll make a PR, if you're fine with it?

Alternative would be to make it configurable, but I don't think human-readable things in binary cbor is a good default.
