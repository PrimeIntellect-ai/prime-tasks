[Feature]: include changelog creation within the release workflow
### Describe your feature

Uplift can perform a `release` against a repository that currently bumps files and tags a repository using the latest calculated semantic version. Changelog generation is included as a separate command and should also be incorporated within the release workflow.

### Your potential solution

Wire the changelog task into the existing release workflow

### Any additional information?

_No response_

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional contract requirements

- When `release` creates its version tag, the tag subject must contain `ci(uplift):`.
