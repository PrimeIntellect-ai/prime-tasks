Updating an exported service is not handled
**What happened**:
In a working setup, when a service is exported, we can successfully access it from remote clusters.
If we update the service (like the port numbers) in the origin cluster, the corresponding serviceImport is not updated.

### Additional contract requirements

- When a ServiceExport is synchronized, its `ServiceExportSynced` condition must be observed first with status `False` and reason `AwaitingSync`, and then with status `True` and an empty reason.
- If an exported Service is updated to an unsupported type, its `ServiceExportSynced` condition must be observed with status `False` and reason `NoServiceImport`.
