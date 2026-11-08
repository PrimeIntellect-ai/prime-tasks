Snapshot dependencies
Just updated to 1.34.0, and I bumped into this:

https://github.com/awslabs/smithy/blob/1ce05b2640eb006c737d8cb278a33ca2c31ad821/smithy-cli/src/main/java/software/amazon/smithy/cli/dependencies/MavenDependencyResolver.java#L155-L157

Snapshot dependencies not being supported seems like a very strange limitation - we used to rely on snapshots a lot for developing new features in a Smithy library, while being able to test out things like packaging, LSP support, etc. without committing to a stable release.

Why is this requirement in there? Could it be relaxed? After the recent change to the LSP, which now uses this custom resolver rather than Coursier (which allows snapshots), it's going to be a problem for orgs that share Smithy libraries (e.g. for custom protocols) between repositories.

### Additional contract requirements

- Maven SNAPSHOT dependencies must be usable through Smithy's custom resolver: after a SNAPSHOT dependency is declared with configured Maven repositories, the resolver must be able to fetch its published artifact and return it for use by Smithy.
