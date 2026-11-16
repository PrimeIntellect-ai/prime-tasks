Prevent deletion of pim:Storage containers
We currently have a check to prevent deletion of the root container. As mentioned in https://github.com/solid/community-server/issues/381#issuecomment-737277297 we should instead check if the container is a `pim:Storage` container instead.

We probably also want to update our pod provision to make sure the root of the pod is set as such a storage then.

### Additional contract requirements

- When deletion of a `pim:Storage` container is rejected, throw a `MethodNotAllowedHttpError` with the exact message `Cannot delete a root storage container.`
