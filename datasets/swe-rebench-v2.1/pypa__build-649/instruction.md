RFE: Mark tests that require internet?
Would you be willing to consider a mark or option to exclude tests that require internet access (ie, PyPI)?

Use case would be: running tests in package build systems that prohibit internet access.

### Additional contract requirements

Register a pytest marker named `network` for tests that require internet access.
