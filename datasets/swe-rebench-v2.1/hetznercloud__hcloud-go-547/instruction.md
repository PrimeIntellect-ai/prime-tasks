fix(metadata): trim responses before parsing
### TL;DR

Responses from metadata service are not trimmed before parsing. They rely on underspecified behaviour of the metadata service api.

### Expected behavior

Before parsing the response, we should at least trim any excessive whitespace

### Observed behavior

If the response contains any whitespace (like a newline at the end of it), the parsing of some of the fields fails.

This applies to `InstanceID()`, `PublicIPv4()`.

In addition, the return values of all other functions would also include the additional whitespace, leading to unexpected results downstream.

### Minimal working example

_No response_

### Log output

_No response_

### Additional information

_No response_
