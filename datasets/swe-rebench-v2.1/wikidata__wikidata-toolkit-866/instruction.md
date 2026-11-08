Migrate to <dependencyManagement> to control versions of dependencies
We currently use Maven properties in the root POM to specify the versions of our dependencies, but that only works to control the versions of the dependencies that are directly mentioned in submodules. Using the <dependencyManagement> section would instead let us control the versioning of transitive dependencies as well.

Is that correct @robertvazan?

### Additional contract requirements

- In particular, the resolved version of `commons-io:commons-io` must not be `2.15.1`.
