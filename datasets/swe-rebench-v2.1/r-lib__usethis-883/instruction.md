Optionally allow non-CRAN names in create_package and use_description
It's often useful to have package structures or even just DESCRIPTION files in projects that aren't fully packages or will never go to a repository, but the namespace is only so big and underscores/dashes are useful in project names.  I would like a `check_name=TRUE` argument for `use_description()` and `create_package()` so I can skip the name-checking error and use these functions for more projects.  It could also default to `getOptions(usethis.checkname)`

Happy to write the PR for this if you think the feature should exist.
