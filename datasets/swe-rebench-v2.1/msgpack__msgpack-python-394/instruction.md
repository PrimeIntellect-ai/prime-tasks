Support serializing datetime objects
Since timestamps are now a part of the msgpack spec, shouldn't this library support serializing them?

### Additional contract requirements

Timezone-aware `datetime` values can be serialized as MessagePack timestamps by calling `msgpack.packb(value, datetime=True)`. Unpacking such a timestamp with `msgpack.unpackb(data, timestamp=3)` yields a timezone-aware `datetime` that is equivalent to the original value and is expressed in UTC.
