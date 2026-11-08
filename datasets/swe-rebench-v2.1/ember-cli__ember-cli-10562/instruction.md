For v6, don't error if you're in an ember-cli project when trying to generate a new project
This has been an issue forever, but to change it would be a breaking-change.

If I want to use a specific ember-cli, I may want to declare the version in my package.json.
But, in a monorepo, if I cd to a directory and try to generate a project, ember-cli errors trying to tell me I'm already in an ember-cli project (which isn't correct).

```
<root>/
  package.json # defines ember-cli
  packages/
    # I want to make a new package here (or app)

```
