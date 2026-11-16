Consider renaming Config.UidMappings and GidMappings to UIDMappings and GIDMappings
### Description

As noted by @thaJeztah [here](https://github.com/opencontainers/runc/pull/3717#discussion_r1259674639)

> Not for this PR (as it's existing code), but we should look at properly naming these fields as well (UIDMappings , GIDMappings)

We should probably rename the config fields to have capitalized UID/GID.

Fiurthermore, IIRC, when I added the UIDMappings and GIDMappings for mounts in that PR, I tried to name them the same way it is in the config (UidMappings and GidMappings) but the linter complained about it.
