Ability to use multiple generateNotes plugins
## New feature motivation

Far as I've seen on here and in documentation generateNotes only allows 1 plugin currently (please correct me if I'm wrong).

But wouldn't it be nice to easily prepend/append release note bits to the default release note generator?

Use case; currently have a graphql-server that's checked into version control, I run semantic release on it to generate release info (notes, tags, etc.). I also happen to have a script that generates a diff (in .md informational form) between the graphql schema's from a previous release and the current working directory. Would like to append this to the default release notes.

Current way of doing this would have me write a custom plugin that calls the default release note generator and then calls my bash script to append the schema differences.

## New feature description

- The generateNotes step should accept an array
- Way of resolving the generateNotes plugins should handle an array
- All plugin output should be present in the notes

Guessing the order/keeping the order might be an issue here?
