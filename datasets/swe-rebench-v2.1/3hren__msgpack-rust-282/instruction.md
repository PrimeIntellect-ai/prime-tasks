rmpv read_value has no depth limit
I am using `rmpv::decode::read_value` to do some parsing and am running into stack overflows from this crate when fuzz testing my code:

```
# ...snip...
    #186 0x103c9be86 in rmpv::decode::value::read_value::h598f53b10a56f428+0x1596 (packet:x86_64+0x100086e86)
    #187 0x103ca380b in rmpv::decode::value::read_array_data::h9144944be4d4fde4+0x20b (packet:x86_64+0x10008e80b)
    #188 0x103c9be86 in rmpv::decode::value::read_value::h598f53b10a56f428+0x1596 (packet:x86_64+0x100086e86)
    #189 0x103ca380b in rmpv::decode::value::read_array_data::h9144944be4d4fde4+0x20b (packet:x86_64+0x10008e80b)
    #190 0x103c9be86 in rmpv::decode::value::read_value::h598f53b10a56f428+0x1596 (packet:x86_64+0x100086e86)
    #191 0x103ca380b in rmpv::decode::value::read_array_data::h9144944be4d4fde4+0x20b (packet:x86_64+0x10008e80b)
    #192 0x103c9be86 in rmpv::decode::value::read_value::h598f53b10a56f428+0x1596 (packet:x86_64+0x100086e86)
    #193 0x103ca380b in rmpv::decode::value::read_array_data::h9144944be4d4fde4+0x20b (packet:x86_64+0x10008e80b)
# ...snip...
```

### Additional contract requirements

- The maximum container nesting depth is the public constant `MAX_DEPTH` in `rmpv::decode`, whose value is `1024`. A value whose container nesting depth is exactly `MAX_DEPTH` is within the limit; `Error::DepthLimitExceeded` is returned only when the nesting depth exceeds `MAX_DEPTH`.
- `read_value_ref` enforces the same `MAX_DEPTH` limit as `read_value`.
