Support container-runtime bootstrap argument
**Is this a BUG REPORT or FEATURE REQUEST?**:
Feature
**What happened**:
Kubernetes is deprecating the docker runtime in 1.22 . EKS AL2 AMIs now support configuring the container runtime through the `--container-runtime` flag. We should support this argument so that users can migrate on their own terms from dockerd to containerd.

### Additional contract requirements

- `(*EKSConfiguration).Validate` returns exactly the error message `validation failed, 'bootstrapOptions.containerRuntime' must be one of [containerd dockerd]` when `BootstrapOptions.ContainerRuntime` is set to a value that is not `containerd` or `dockerd`.
- When `BootstrapOptions.ContainerRuntime` is set, the user data returned by `(*EksInstanceGroupContext).GetBasicUserData` contains the substring `--container-runtime <value>` (for example `--container-runtime containerd`).


- In the bootstrap argument list, place `--container-runtime <value>` immediately after `--use-max-pods false` and immediately before `--b64-cluster-ca <cluster-ca>`.
