Batch apply changes per-branch
Proposal: Refactor code so changes are grouped/applied per-branch.

An example use case is when the a dependency is updated across multiple `package.json` files in the same (mono)repository. In this case it would be best if all commits could be applied together at the same time.

This would probably also be a prerequisite to getting dependency groups (#10) working elegantly, because multiple dependencies would all be combined into a single PR.
