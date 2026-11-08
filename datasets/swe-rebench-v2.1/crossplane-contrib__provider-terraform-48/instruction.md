Workspace object hangs when terraform plan fails for destroy
### What happened?
The Workspace object is hung after delete was requested because the Observe is failing.  The terraform plan command fails because the AWS VPC object that the terraform is referencing has already been deleted:

```
Status:
  At Provider:
  Conditions:
    Last Transition Time:  2022-04-08T16:37:35Z
    Reason:                Deleting
    Status:                False
    Type:                  Ready
    Last Transition Time:  2022-04-08T16:38:06Z
    Message:               observe failed: cannot diff (i.e. plan) Terraform configuration: no matching ec2 vpc found
    Reason:                ReconcileError
    Status:                False
    Type:                  Synced
Events:
  Type     Reason                         Age                      From                                Message
  ----     ------                         ----                     ----                                -------
  Warning  CannotObserveExternalResource  3m17s (x4536 over 5d5h)  managed/workspace.tf.crossplane.io  cannot diff (i.e. plan) Terraform configuration: no matching ec2 vpc found
```

Removing the finalizer finishes the delete process on the Workspace but there needs to be a way to destroy the workspace when plan fails on destroy.

### How can we reproduce it?
Create a composition that creates a VPC.ec2.aws resource and references that resource in a Workspace, using data "aws_vpc".

When the claim gets deleted, if the VPC object is deleted from AWS before the Workspace delete executes, the problem occurs.

### What environment did it happen in?
Crossplane version: 1.7

* Cloud provider or hardware configuration AWS
