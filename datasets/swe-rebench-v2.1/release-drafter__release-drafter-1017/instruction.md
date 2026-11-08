Provide $REPOSITORY as a template variable
My changelog has the link to create new issues in the text. Since there are 4 repositories in the project, which share the same changelog format, I need to have a way to use the same configuration file in all the repos.

That would be easier if I could reference the repository name in the changelog, so I could do something like
```md
... please [file an issue](https://github.com/WordPress/$REPOSITORY/issues/new). Thanks ...
```

I can understand that this is a niche case, so I'd love to contribute to make it happen. I believe to add new variables, changes must be made here?
https://github.com/release-drafter/release-drafter/blob/4ace3797ecb80529b66a470b7ea172a8ab5cd0b7/lib/releases.js#L269

### Additional contract requirements

- Also provide `$OWNER` as a template variable, replaced with the current repository owner.
