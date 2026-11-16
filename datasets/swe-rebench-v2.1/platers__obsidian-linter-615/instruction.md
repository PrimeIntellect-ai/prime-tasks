Bug: `YAML Title Alias` rule fails if the note name starts with exclamation mark `!`
## Describe the Bug

`YAML Title Alias` rule fails if the note name starts with exclamation mark `!`

## How to Reproduce

1. Create a note named `!Note.md`
2. Apply `YAML Title Alias` rule to it

## Expected Behavior

No errors

## Actual Behavior

```
logger.ts:21 [Obsidian Linter] Lint File Error in File '!Note.md':
Error "YAML Title Alias" encountered an error in the yaml:  unknown tag !<!Note> (2:1)

 1 | title: !Note
 2 |
-----^
YAMLException: unknown tag !<!Note> (2:1)

 1 | title: !Note
 2 |
-----^
    at generateError (plugin:obsidian-linter:2695:10)
    at throwError (plugin:obsidian-linter:2698:9)
    at composeNode (plugin:obsidian-linter:3603:7)
    at readBlockMapping (plugin:obsidian-linter:3353:11)
    at composeNode (plugin:obsidian-linter:3546:78)
    at readDocument (plugin:obsidian-linter:3678:3)
    at loadDocuments (plugin:obsidian-linter:3720:5)
    at load$1 (plugin:obsidian-linter:3738:19)
    at loadYAML (plugin:obsidian-linter:4602:23)
    at YamlTitleAlias.apply (plugin:obsidian-linter:53076:24)
```

### Additional contract requirements

The `YAML Title` rule must quote the title when the title would otherwise be parsed by YAML as a value that is not a plain string, so that the generated frontmatter is valid YAML. With the default `title` key, a heading `# <title>` must produce `title: "<title>"` (the title wrapped in double quotes) for titles that begin with a YAML indicator character (`!`, `@`, `%`, `&`, `*`, `-`, `[`, `]`, `{`, `}`, `|`, `>`) or that contain a `#` preceded by a space.

As a result, applying the `YAML Title` rule and then the `YAML Title Alias` rule to a note named `!Note.md` with heading `# !Note` must not raise an error.
