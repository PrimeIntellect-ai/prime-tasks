aws: expose a list of supported services (regions?)
## Abstract

In order to be able to use the `aws.Ingester` type correctly, the user needs to know the name of the service they want to ingest. This is not always obvious - for example, `AmazonEC2` is used and not just the expected `EC2`. The users of the library should be able to retrieve a list of all supported services so that it can be displayed or manipulated in any other way.

## Implementation details

A function in the `aws` package that returns a `[]string` containing a list of all supported AWS services that can be ingested.

## Suggestions/ideas

This list can also be used internally to validate the requested service, before issuing a request to AWS.

### Additional contract requirements

- The function that returns the list of supported services is named `GetSupportedServices` and has the signature `func GetSupportedServices() []string`.
- The AWS services supported by Terracost are `AmazonEC2`, `AmazonRDS` and `AWSELB`. `GetSupportedServices` returns exactly these names (in any order), and each of them is accepted by `NewIngester`.
