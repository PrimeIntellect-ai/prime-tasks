[Feature]: Aggregate dependencies in root Cargo.toml
### What is the feature you would like to see?

We are currently specifying most dependencies of member crates directly, but we should instead define the dependency in the root Cargo.toml, and then do `DEPENDENCY_NAME.workspace = true` in member crates.

The rationale is that this way, we ensure we're using a single version of a dependency.

This may not make sense for all dependencies, so this should be judge on a case-by-case basis.

### Contribution Guidelines

- [X] I agree to follow this project's Contribution Guidelines
