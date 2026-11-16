Proposal: Specify no-pull per service/container via label
I am watching multiple containers with watchtower. One of them only gets local image updates (built via cron). It would be nice if watchtower could restart/update that container. But currently, I get this error message:

`Unable to update container "/name_name_1": Error response from daemon: pull access denied for custom/name, repository does not exist or may require 'docker login': denied: requested access to the resource is denied. Proceeding to next.`

It would be nice to be able to specify the no-pull option just for this container via a label.

### Additional contract requirements

- The per-container no-pull setting is controlled by the container label `com.centurylinklabs.watchtower.no-pull`.
- The container type in package `pkg/container` exposes this setting through a public method `IsNoPull() bool`. It returns `true` when the label is present and parses to a true boolean value, and `false` when the label is absent, cannot be parsed as a boolean, or parses to false.
- When a container's no-pull setting is true, watchtower must not pull that container's image while checking whether the container is stale.
