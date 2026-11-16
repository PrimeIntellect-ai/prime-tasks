Provide fully decoded jwt object to key callback
Hi,

it would really simplify my integration scenario if the complete decoded JWT object is passed to the key callback here:

https://github.com/nearform/fast-jwt/blob/master/src/verifier.js#L327

I want to dynamically resolve the key based on the issuer (iss) and need to have access to the payload.

Unfortunately this would be a breaking change because the header is now not the root level object anymore. Perhaps it could make sense to make this configurable?

What do you think?

Cheers,

Julian
