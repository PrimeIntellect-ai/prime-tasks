For join, the same tag in multiple input files should not be seen as a conflict
**Problem**
I have two (or more) OAS files that use the same tag to tag some operations. Running `openapi join` results in an error about "Conflict on tags."

**Improved Solution**
I don't see why it would be considered a conflict if multiple schemas that you're trying to join together use the same tag names. Maybe display a warning, but it's not an irreconcilable crisis that should prevent the join from succeeding. Use the first (or the last) description of the tag--authors can figure that out.

This is what is already done with components that are defined in multiple input files but are identical. It's not considered an error.

Perhaps have a command line option to let the user choose what to do if the same tag name is used in multiple files:
1. Allow it.
2. Error out.
3. Prefix with info property
4. Prefix with filename

**Describe alternatives you've considered**
I tried using prefix-tags-with-info-prop but that gave me different tags with goofy names, which was not at all useful.

### Additional contract requirements

- The `without-x-tag-groups` option makes `join` tolerate the same tag name appearing in multiple input files: the join succeeds and writes the merged `openapi.yaml` instead of reporting a tag conflict.
- When `without-x-tag-groups` is used and a tag name occurs in more than one input file, the description of that tag in the merged output is taken from the first input file that defines it.
- `without-x-tag-groups` also suppresses the automatic creation of `x-tagGroups` in the merged output.
- Without `without-x-tag-groups` (and without any other tag option), a tag name that occurs in more than one input file is still reported as a conflict and the join does not write the merged file.
- The options `prefix-tags-with-filename`, `prefix-tags-with-info-prop` and `without-x-tag-groups` are mutually exclusive: passing more than one of them is an error.
