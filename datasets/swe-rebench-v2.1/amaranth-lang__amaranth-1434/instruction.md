`stream.Signature` should allow setting the init value for the payload
This for example does not work:

```python
class BitSerializer(wiring.Component):
    def __init__(self, *, width, length):
        self._length = length

        super().__init__({
            "shift": In(1),
            "stream": In(stream.Signature(data.StructLayout({
                "o":  data.ArrayLayout(width, length),
                "oe": 1
            })), init={"payload": {"oe": 1}}),
            "buffer": Out(io.FFBuffer.Signature("o", width)),
        })
```

but could be valuable for the same reason `io.Buffer.Signature`'s `oe` member has `init=1`.

### Additional contract requirements

`stream.Signature` accepts a keyword argument `payload_init` (default `None`). When it is provided, the payload signal of the interface returned by `Signature.create()` has its `.init` attribute equal to `payload_init`. This holds for structured payload shapes as well as scalar ones: for a payload shape such as `data.StructLayout({"o": data.ArrayLayout(width, length), "oe": 1})`, passing `payload_init={"oe": 1}` sets the `oe` field of the payload's initial value to 1.
