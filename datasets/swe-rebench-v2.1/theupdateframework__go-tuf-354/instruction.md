Unable to initialize client without fetching from remote
Before calling `client.Update` or `client.UpdateRoots`, it is expected that the client has been initialized with `client.Init`. [`Init`](https://github.com/theupdateframework/go-tuf/blob/master/client/client.go#L114) uses a set of root keys, pulls the latest `root.json`, verifies it with those keys, and saves it locally.

The issue is there's no guarantee that the latest root can be verified using the set of root keys. For example, let's say a project is shipped with the first `root.json`. Before a new root signing, one key is rotated. After 5 signings, all keys used to sign the remote `root.json` will have been rotated. `Init` will fail, and there's no other way to directly initialize the client.

The proper way to initialize a client would be to initialize the client with a local root, then walk and verify the chain using `Update` or `UpdateRoots`. I'd like to propose that `Init` take the local `root.json` to initialize the database, and not make any calls to the remote to fetch the latest `root.json`.

Another option would be for `Init` to take the set of root keys and threshold, its current API, and call `UpdateRoots` as part of initialization. I would prefer that this not be the default, for those who don't want to initialize a client with the latest root.

cc @asraa

### Additional contract requirements

- The client type in package `github.com/theupdateframework/go-tuf/client` exposes a public method `Init(rootJSON []byte) error`.
- `Init` returns a non-nil error when the supplied bytes are not valid JSON, when the root metadata fails verification.


- - When root signature verification fails, `Init` returns `verify.ErrInvalid`.
- - `Init` accepts expired root metadata.
