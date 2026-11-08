clk is not output in market recorder
The `clk` field is hardcoded to `None`, ignoring whatever was received in the raw stream:

https://github.com/liampauling/flumine/blob/8ae3879a2cb82ae0ebbb648beee93608551fe9f4/examples/strategies/marketrecorder.py#L64-L71

In the interests of

1. Replicating the raw stream as closely as possible
2. Not discarding any data

it would be good if the received `clk` value could be output

### Additional contract requirements

- The example market recorder (`examples/strategies/marketrecorder.py`) must write the received clock token into each recorded JSON line under the `"clk"` key instead of the hardcoded `None`. Each recorded line keeps the existing shape `{"op": "mcm", "clk": <clk>, "pt": <publish_time>, "mc": [<datum>]}`.
