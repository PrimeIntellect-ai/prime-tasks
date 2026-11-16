bash: separate visual from inserted value
Thanks to https://stackoverflow.com/a/10130007 values have descriptions, but at them moment also contain prefix/suffix.
Change the completion values to:
```handlebars
{{insertedValue}}\t{{displayValue}} ({{description}})
```

And return either part before or after tab in script.

### Additional contract requirements

- In Bash completion, use the field before the tab as the value inserted into the command line, and the field after the tab as the candidate’s visual value.
- For the `alias` completion, emit `alias\taction (action example)`, displaying the canonical command name `action`.
