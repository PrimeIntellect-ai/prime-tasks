Add `request` emit
This should be similar to the `response` event, except that it emits information on an outgoing request before making the request.

### Additional contract requirements

The `request` event must fire before each outgoing request, including requests made while following a redirect. Each event provides listeners with a parsed URI object identifying the outgoing request (including its full `href`) and the options used for that request.
