Timeout for the RPC server should be configurable
Right now it's constant at one second

### Additional contract requirements

The RPC server's HTTP read and write timeouts must be configurable through the
node configuration file. The configuration exposes two settings in the `[RPC]`
section named `ReadTimeoutInSec` and `WriteTimeoutInSec`, both expressed in
seconds and both defaulting to `60`. The configured values must be applied to
the RPC HTTP server's read and write timeouts.
