ngclient: allow metadata dir to not exist
Currently we expect the local metadata dir to exist when Updater initializes. This made sense when we also expected the caller to put the initial root into the local metadata dir, but we no longer require that (as the bootstrap argument was added).

It should be ok for the metadata dir (and likewise the artifact dir) to not exist when Updater starts up, and the Updater should create those dirs.
