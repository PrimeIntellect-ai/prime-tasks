Limit garbage collection to workspace directories with UUID names
### What happened?
Garbage collection is monitoring all directories under /tf and comparing them to the list of provisioned Workspaces.  Any directory that does not have a valid Workspace UUID is removed.

It would be helpful to be able to use the /tf directory as a provider cache to eliminate the need to duplicate all providers in every workspace.  In order for this to work we need Garbage Collection to not remove the provider cache directories.

### How can we reproduce it?
Create a ControllerConfig for provider-terraform and specify an env variable TF_CACHE_DIR=/tf

Observe that there is a cache directory under /tf called registry.terraform.io and that this directory gets removed when garbage collection runs (the timestamp is updated when it gets recreated by the next terraform init)

This issue tracks a minor enhancement that will keep Garbage Collection from removing any directory that is not a Workspace UUID name.
