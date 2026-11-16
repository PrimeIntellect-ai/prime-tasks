Rename loadTemplate function from the project packer
To avoid confusion, we should rename `loadTemplate` into `loadRemoteTemplate`, because it is solely used when loading a remote template via the current github gateway implementation.
