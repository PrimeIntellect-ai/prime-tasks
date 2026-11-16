Add InvalidSignature exception
Right now the [`jws.decode()`](https://github.com/jpadilla/pyjwt/blob/e0aa10ee586bf010ce9a99c5582ee8dc9293ba1e/jwt/api_jws.py#L206) method raises a `DecodeError` when the signature verification failed. I would like to propose adding a dedicated `InvalidSignatureError` or `SignatureVerificationError` exception class.

The reasoning behind this: I'd like to implement a key-rotating feature that checks for one key and if the signature verification fails checks for the other key. The claims, algorithm, and whatnot still need to be validated. The only solution I see right now is catching the `DecodeError` and checking for `e.args[0] == 'Signature verification failed'` which feels super dirty.

Please let me know what you think about this. I'm happy to provide the corresponding backward compatible patch.
