Automerge pin requests
Default config option is to pin dependencies that were in a range. Why not automerge them too?

### Additional contract requirements

- When a dependency specified as a range (for example `^1.0.0`) is pinned to the latest matching version, the resulting pin upgrade is automerge-enabled by default (its `automergeEnabled` flag is `true`, the same flag other upgrades use). A pin PR whose status checks pass is merged automatically without extra configuration.
- Existing automerge behaviour for non-pin upgrades is unchanged: with `automerge` set to `any` or `minor`, the upgrades that qualify keep `automergeEnabled: true`, and the others keep `automergeEnabled: false`.
