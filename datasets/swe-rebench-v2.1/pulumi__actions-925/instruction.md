Support the `--exclude-protected` on destroy
## Hello!
<!-- Please leave this section as-is, it's designed to help others in the community know how to interact with our GitHub issues. -->

- Vote on this issue by adding a 👍 reaction
- If you want to implement this feature, comment to let us know (we'll work with you on design, scheduling, etc.)

## Issue details

<!-- Enhancement requests are most helpful when they describe the problem you're having as well as articulating the potential solution you'd like to see built. -->
For similar reasons outlined in the [issue](https://github.com/pulumi/pulumi/issues/6539) that resulted in the `--exclude-protected` being added to the CLI, it would be good to be able to provide this flag in the GitHub Action.

### Additional contract requirements

- The action accepts an `exclude-protected` input (a boolean, default `false`).
- `makeConfig()` (in module `src/config.ts`) returns a configuration object whose `options` property includes a boolean field `excludeProtected`, defaulting to `false` and derived from the `exclude-protected` action input.
