problem using modules with a relative path
We found a problem using modules with a relative path in the workspace remote like this.

module "db_option_group" {
  source = "../db_option_group"

When try to install we get this error \:

2022-08-16T21:03:15.466Z DEBUG controller-runtime.manager.events Warning {"object": {"kind":"Workspace","name":"rds-remote","uid":"62c9fe78-b7df-4796-9eba-ba9700f271dd","apiVersion":"tf.crossplane.io/v1alpha1","resourceVersion":"18459415"}, "reason": "CannotConnectToProvider", "message": "cannot initialize Terraform configuration: unreadable module directory"}

We saw  is made a change to don't use --from-module on previous release, but It seen don't working


What environment did it happen in?
Crossplane version: last version


Cloud provider: AWS
Kubernetes version: v1.21.12
Kubernetes distribution:  EKS
OS VERSION: 18.04.6 LTS (Bionic Beaver)
Kernel: Linux runway-devenv 4.15.0-176-generic #185-Ubuntu SMP Tue Mar 29 17:40:04 UTC 2022 x86_64 x86_64 x86_64 GNU/Linux

### Additional contract requirements

- The `Workspace` spec exposes an optional `entrypoint` field. In Go it is the
  exported `Entrypoint` field of type `string` on `WorkspaceParameters` in the
  `apis/v1alpha1` package, serialized as `entrypoint`.
- When `entrypoint` is set, Terraform is initialized in that subdirectory of the
  checked-out module; when it is empty, Terraform is initialized in the root of
  the checked-out module. This lets a module that references a sibling module
  through a relative path (for example `source = "../db_option_group"`) resolve,
  because the whole repository is checked out.
