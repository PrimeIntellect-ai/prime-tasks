use workspace dependencies
It's easier to maintain and also easier to see what is used by using workspace dependencies.
For the crate itself it doesn't change much and for the user it works the same.
It's however easier ergonomics for maintainers and contributors.

I can open a PR for you if you want,
pretty easy to transition to it thanks to a tool by luke:
https://github.com/mainmatter/cargo-autoinherit

### Additional contract requirements

Across workspace member crates, external dependencies are maintained centrally: each external dependency used by a member is declared in the root `[workspace.dependencies]` catalog, and member manifests inherit that declaration instead of repeating its version or default-feature configuration. A member may still select additional features for its own use.
