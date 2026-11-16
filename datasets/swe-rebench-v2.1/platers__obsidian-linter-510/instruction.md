Bug: Linter fails to property delimit frontmatter tags separated by commas
## Describe the Bug

If a note's frontmatter contains tags that are delimited by a comma without a trailing space, linter treats them as a single tag.

## How to Reproduce

I have attached the data.json file. [data.json.txt](https://github.com/platers/obsidian-linter/files/10057774/data.json.txt)

### Example 1

include in frontmatter YAML:

`tags: tag1,tag2`

### Example 2

include in frontmatter YAML:

`tags: tag1,tag2, tag3`

Linting the file produces an incorrect result when the tags array is split into a multiline array:

Example 1 produces no result, even though it contains two tags.

Example 2 produces a note that now only contains 2 tags ("tag1,tag2" and "tag3") even though before linting the note contained three tags.

## Expected Behavior

Linter should parse the tags array **exactly** how Obsidian parses the tags array.

Example 1 should produce a multiline tags array with two tags.
Example 2 should produce a multiline tags array with three tags.

## Device

- [x] Desktop
- [?] Mobile
