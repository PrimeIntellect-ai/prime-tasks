getSignedUrl is broken in version 2.382.0
I've gotten the latest version of the SDK - which right now is 2.382.0 - and I'm experiencing an issue with *getSignedUrl*. The method always returns:

https://s3.us-east-2.amazonaws.com/

... no matter what. When I downgrade back to ^2.381.0, I have no problems.

Thanks,
Andrew

### Additional contract requirements

A URL returned by `getSignedUrl` must include signing information in addition to identifying the requested bucket and object key.
