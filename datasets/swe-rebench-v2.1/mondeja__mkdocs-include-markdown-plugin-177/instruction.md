Log warning when failing to find `start` or `end`
Currently, if a `start` or `end` delimiter is not detected, the include tag silently handles this. This really ought to be logged via warning.

### Additional contract requirements

- The warning text must include the exact formatted message `Delimiter {delimiter_name} '{delimiter}' of '{directive}' directive at {includer_path}:{line_number} not detected in the file {included_path}`, with placeholders replaced by the missing delimiter name (`start` or `end`), its delimiter string, the directive name (`include` or `include-markdown`), and the relevant paths and directive line number.
