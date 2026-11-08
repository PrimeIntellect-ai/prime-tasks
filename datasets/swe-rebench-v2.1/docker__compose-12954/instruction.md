Having a `volume`   command
### Description

Not much needs to be said I suppose. Having a `volume` command, context-aware of the services running in the compose file would make it a lot easier to delete, prune, and inspect volumes related to the services. The main usage for this is *not having to type the whole project name - service name - volume name, and not having to browse amidst all volumes you have available on a host.

If pointed in the right direction I can do my best to provide a patch for this.

### Additional contract requirements

- The command is registered on the Compose root command under the exact name `volumes`.
- When one or more service names are given as arguments, only the volumes used by those services are listed.
