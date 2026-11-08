add support for signed integers encoding/decoding
Netlink has support for [signed integer attributes](https://elixir.bootlin.com/linux/v5.10.15/source/include/net/netlink.h#L104), which the library currently is missing. These are for example required when talking to rtnetlink to [set and modify the file descriptors of XDP programs](https://elixir.bootlin.com/linux/v5.10.15/source/net/core/rtnetlink.c#L2911) loaded to the links.

Providing these through the library would offer tested and validated methods of encoding these to the users, blocking workarounds through `Bytes` and `Uint32` implementations that could lead to bugs.

I've done some minor work on this on a [fork](https://github.com/fbegyn/netlink/tree/f-signed-ints), which is sufficient for my application, but can expand and modify it if to be upstreamed if this deemed as a desired feature.

### Additional contract requirements

Provide public `AttributeEncoder` methods `Int8`, `Int16`, `Int32`, and `Int64` that encode values as signed integers of the corresponding widths. Provide matching `AttributeDecoder` methods with those names that return signed values of the corresponding widths. Signed values, including negative values, must be preserved; multibyte values use the encoder and decoder byte order. A decoder reports an error when an attribute payload length does not match the requested width.
