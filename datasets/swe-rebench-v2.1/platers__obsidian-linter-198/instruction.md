Colon in H1 invalidates YAML
I used some titles with colons (e.g., `#V02: A title`).
The automatic insert in the yaml title as `title: V02: A title` results in an invalid yaml (reason: double colon).

Suggestion: Some characters may be filtered before inserting them in the yaml.

Edit: On a second thought, the titles could just be inserted in quotation marks. ;)

### Additional contract requirements

- When inserting a long title into YAML, keep the value unquoted and on one line. For example, the output line for the tested title must be `title: Very long title 1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890`.
