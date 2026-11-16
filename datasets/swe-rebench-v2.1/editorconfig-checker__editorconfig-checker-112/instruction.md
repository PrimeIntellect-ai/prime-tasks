[Request] Support max_line_length

### Additional contract requirements

A configured `max_line_length` in an applicable EditorConfig section must be honored during file validation: lines longer than its limit are reported as validation errors. Lines at or below the limit are not reported for this rule.
