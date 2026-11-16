Turtle parser: Carriage returns in literals delimited by a single quote (single or double) are not flagged.
### Version

5.2.0

### What happened?

A literal in turtle in a single quoted section is not allowed to have a [carriage return in them](https://www.w3.org/TR/turtle/#turtle-literals).
Validation should detect such cases and report errors.

### Relevant output and stacktrace

_No response_

### Are you interested in making a pull request?

None
