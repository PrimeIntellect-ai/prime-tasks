Panics on "revoke refresh" API call
User reported panics when attempting to use the revoke refresh token API call.

https://groups.google.com/forum/?utm_medium=email&utm_source=footer#!msg/dex-dev/165C3bUP6ao/c_e6rDrEAAAJ

The following code looks kinda suspect https://github.com/coreos/dex/blob/e10fddee2e79f7a0cdeba511fd5936cf19511bc9/server/api.go#L271
