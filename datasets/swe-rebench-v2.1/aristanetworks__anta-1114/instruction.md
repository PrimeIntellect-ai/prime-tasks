feat(anta.tests): The source field of VerifyReachability Host model should be optional
When `source` is `None`, that means we don't provide a source to the ping command and let EOS decides the source.
