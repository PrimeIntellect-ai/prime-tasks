bug: ValueError: Out of range float values are not JSON compliant
### Singer SDK Version

0.34.1

### Is this a regression?

- [ ] Yes

### Python Version

3.9

### Bug scope

Taps (catalog, state, etc.)

### Operating System

MacOS

### Description

I get `ValueError: Out of range float values are not JSON compliant`  when trying to sync Amazon Document DB collection.

The probably reason is that `simple_json.dumps()` has `allow_nan=False` default, while standard `dumps()` function from standard `json` library has `allow_nan=True`.

As there is no way to pass configuration from outside could we add this functionality? I can introduce relevant fix.

### Code

_No response_

### Additional contract requirements

- When `SimpleSingerWriter.write_message()` writes a `RecordMessage`, non-finite float values (`NaN`, positive infinity, and negative infinity) in the record must be serialized as JSON `null`. For the test record, the exact output is `{"type":"RECORD","stream":"test","record":{"id":1,"name":null}}\n`.
