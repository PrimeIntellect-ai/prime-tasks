Multiple fields for formatter config can mess up default values
If the `basic` formatter is configured like so:
```
formatter:
  include_document_start: true
```
The default value of 2 for `Indent` is lost, and the indentation will end up being the `yaml.v3` default of 4.
