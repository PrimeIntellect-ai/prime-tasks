Workspaces with no resources run terraform apply on every reconcile
### What happened?
If a Workspace has no resources, only outputs for example, the current Observe logic returns ResourceExists: false every reconcile because there are 0 resources returned from terraform state list.

If the Workspace has outputs and terraform plan has returned no delta then the ResourceExists attribute can be set to true


### How can we reproduce it?
Create a Workspace that has no resources, only outputs, and observe in the debug logs that the Workspace is constantly calling the Update/Create method on every loop

### What environment did it happen in?
Crossplane version: 1.8.1
