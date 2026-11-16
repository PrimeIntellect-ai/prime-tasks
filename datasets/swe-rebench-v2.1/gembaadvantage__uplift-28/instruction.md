[Feature]: support annotated git tags
### Describe your feature

Currently uplift only supports lightweight tags. These are effectively just a pointer to a commit at a certain point in time and are seen as temporary tags. Annotated tags are stored as full objects within the git database and support the following features:

1. Tagger details (name, email etc)
2. GPG signed tags

### Your potential solution

Support the options of lightweight/annotated tags within the uplift config YAML file

### Any additional information?

_No response_

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional contract requirements

- The `config.Uplift` configuration must include a boolean `AnnotatedTags` field; setting it to `true` selects annotated tags, while a false or unset value keeps tags lightweight. When `AnnotatedTags` is `true`, the annotated tag contents must include the configured `CommitMessage`; in the tested case, they must include `this is an annotated tag`.
