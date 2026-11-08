Upstream gherkin breaks if language is not recognised
Cucumber repo has an example with an unknown language, which should cause a parse error. We default back to `en` I believe

### Additional contract requirements

- In `GHERKIN_32` compatibility mode, parsing a feature with an unrecognized language must produce a parse error.
