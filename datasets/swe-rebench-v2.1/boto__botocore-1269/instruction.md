API Gateway Documentation Duplicate AWS CLI targets
This is coming from aws/aws-cli#2786. Looking over the botocore service files for API gateway, there are multiple links with the "AWS CLI" target including the `get-method` method. Needs to be something more specific to avoid sphinx target errors on the `aws-cli` side. Since I'm anticipating that these service files are auto generated I'm holding off on any sort of pull request.

### Additional contract requirements

- When ReSTStyle renders a hyperlink, its reStructuredText link markup must end with `__` rather than `_`; for example, a link with text `example` and href `http://example.org` must serialize as `` `example <http://example.org>`__ `` followed by a space.
