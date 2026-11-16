Include custom pages and Patches directory in `--show-paths` option
Quote from PR #142
> We should also include the custom pages directory in the new --show-paths option output, but that's probably best done in a separate PR, in order not to hold up this one.

Acceptance Criteria:
* Using `--show-paths` includes the location of the custom_pages directory in the output
* Tests are created / updated for new and changed code
