Conditional check for cache directories in scanDir method encounters lost+found
As of yesterday it looks like there was some conditional logic added to the scanDir() method of the diskCache struct. This conditional checks whether or not the directories name is equal to a few different values; please see [here](https://github.com/buchgr/bazel-remote/blob/8ac1f9007ce420ff62c7d0a136a0691da80b972c/cache/disk/load.go#L449).

This has caused the remote cache in our environment to go into crashloop after the scanDir method encounters the `lost+found` directory on the linux host, this directory is created by fsck on our ext4 filesystem and will always be recreated even if deleted.
