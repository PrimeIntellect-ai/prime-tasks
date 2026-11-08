Simple block `link-to` not converted
```
{{#link-to 'data-access'}}Accessing the Crates.io Data{{/link-to}}.
```

I don't know why, but the snippet above was not converted to Angle Brackets for some reason 🤔

source: https://github.com/rust-lang/crates.io

### Additional contract requirements

- Also convert `{{#link-to "data-access"}}Accessing the Crates.io Data{{/link-to}}` to `<LinkTo @route="data-access">Accessing the Crates.io Data</LinkTo>`.
