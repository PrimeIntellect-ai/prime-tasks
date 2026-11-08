Allow a user to provide SR Linux topology yaml file with custom platform definition
Currently it is not possible to provide a custom topology yaml; the user has to select a type and this will trigger creation of a bind mount with the matching topology file.

This prevents a user from providing a custom topology file, as two bind mounts would exist - a customer one, and the one from containerlab itself.

We need to check if the bind mount targeting `/tmp/topology.yml` exists, then we should not create the one by containerlab for a selected type. This is an override by a user.

### Additional contract requirements

Add a public function `DestinationBindMountExists(binds []string, dest string) bool` in package `utils` (import path `github.com/srl-labs/containerlab/utils`). It returns true exactly when one of the given bind mount specifications has `dest` as its destination, where the destination is the second colon-separated component of a specification of the form `source:destination[:options]`; the source and any mount options are ignored. It returns false when no entry matches.
