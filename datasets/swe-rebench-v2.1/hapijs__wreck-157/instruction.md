Change "response" Payload
I propose we change the payload we send to "response" handlers to be `err, payload` and just make `payload` a single large object rather than the five parameters we are currently passing. Much easier to maintain and won't introduce breaking changes when we need to add more to it.

### Additional contract requirements

The response event must pass exactly two arguments: the error (or no error) first, and one payload object second. The payload must preserve the actual request, response, request start time, and parsed URI information that was previously supplied as separate arguments; the names used to expose those values are not prescribed. On a failed request, a response object need not be present.
