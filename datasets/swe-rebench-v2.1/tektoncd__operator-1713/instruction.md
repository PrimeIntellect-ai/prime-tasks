Remove Service and Configmap related to Results DB
We should also remove service and configmap related to results DB when we use external DB.

### Additional contract requirements

When an external database is not used, the Results DB Service and ConfigMap remain available among the resources to be reconciled.
