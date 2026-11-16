Colon in H1 invalidates YAML
I used some titles with colons (e.g., `#V02: A title`).
The automatic insert in the yaml title as `title: V02: A title` results in an invalid yaml (reason: double colon).

Suggestion: Some characters may be filtered before inserting them in the yaml.

Edit: On a second thought, [HIDDEN] ;)

### Additional contract requirements

- When an H1 title is serialized into YAML front matter, the YAML must be valid and its title value must preserve the complete H1 text, including punctuation.
