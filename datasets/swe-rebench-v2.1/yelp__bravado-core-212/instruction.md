internally_dereference_refs generates wrong result when discriminators are used in spec
internally_dereference_refs appears to not properly deserialize responses when discriminators are used in the spec and when use_models is enabled. In particular, if the model contains a type and a subtype none of the attributes of the subtype gets deserialized.

Here's an example spec: https://gist.github.com/gstarnberger/4dd7d76b94d7afec87f8a6a141dfd17e

If you call an endpoint that returns `{"score":12345,"type":"subtypeOfResponse"}` as response that response gets deserialized as:

- `subtypeOfResponse(score=12345, type=u'subtypeOfResponse')` (with internally_dereference_refs disabled)
- `subtypeOfResponse()` (with internally_dereference_refs enabled)

Directly accessing the missing attributes still yields a value, but that value doesn't use any models (although use_models is set to True). For example, if score would have been defined as another object type then subtypeOfResponse.score would have returned a dictionary.

Here's the code that I used to reproduce the issue:

Server: https://gist.github.com/gstarnberger/359669829881ca5fa188f5a480820512 (basically just returns the same hardcoded response for any call)

Client: https://gist.github.com/gstarnberger/3701dba50aba719ffc0bf28454485f31

Output of the client when running the code is:

```
False subtypeOfResponse(score=12345, type=u'subtypeOfResponse')
True subtypeOfResponse()
```

### Additional contract requirements

When models are enabled, object-valued properties on a discriminator-selected subtype are deserialized according to their schemas; a property referencing a model definition is returned as an instance of that model.
