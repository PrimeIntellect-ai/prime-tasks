Enhancement: Add Step Functions to support resourcegroupstagging
Per the [AWS docs](https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/supported-services.html) Step Function support the Resource Groups Tagging API.

It looks like there is a custom implementation for tags for step functions. @bblommers is there a special case with Step Functions or is this a simple use-case to add this support?

### Additional contract requirements

- Querying the Resource Groups Tagging API (`get_resources`) with `ResourceTypeFilters=["states:stateMachine"]` returns the Step Functions state machines in the account and region, each with its tags listed in `Tags`.
