Add event for snapshotting in progress
We have a similar event when creating a PVC that we're waiting for the driver to provision.

/kind feature

### Additional contract requirements

- When snapshot creation is in progress, emit a Kubernetes event with type `Normal` and reason `CreatingSnapshot`.
