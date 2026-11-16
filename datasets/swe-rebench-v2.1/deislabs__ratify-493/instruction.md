Store plugins cannot be used from verifier plugins
When executing verifier plugins, Ratify will bundle up and pass all of the configuration needed about a store to a verifier plugin over STDIN. An important field in this flow is `pluginBinDirs`, as that is how Ratify knows where to find plugins - either in the default plugin dir, or a user-provided dir.

[HIDDEN] The effect is that when an out of tree store (ex: anything not `oras`) is resolved, it fails at runtime with an error because the store can't be found under a blank subdir. Ex:

```
    {
      "isSuccess": false,
      "name": "sample",
      "message": "an error thrown by the verifier: plugin command VERIFY failed; failed to find plugin \"oras2\" in paths []",
      "artifactType": "application/spdx+json"
    },
```

Per some code comments nearby, it looks like this used to work, but there has been limited usage of plugin stores outside of the sample in the repo.
