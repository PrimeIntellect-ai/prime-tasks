kn needs the ability top set a default timeout for the service

### Feature request

kn create needs a flag for setting the default timeout for the service

### Use case

I want to create my services with a default timeout of 10 seconds rather than the standard 300 - currently I can't create a service with the timeout of 10 secs and need to post-create change it (in this case using the OpenShift UI/YAML editor) which creates a new revision

There are flags for most things when creating a service but this one (timeoutSeconds) seems to be missing

/kind proposal

### Additional contract requirements

- The flag is named `--timeout` and takes an integer number of seconds.
- The flag is available for `kn service create` and `kn service update`.
- The flag defaults to 300 seconds.
- When the flag is provided, the service's revision timeout is set to the given number of seconds.
- Setting the flag causes a new revision to be created.
