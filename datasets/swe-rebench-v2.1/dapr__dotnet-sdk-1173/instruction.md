GetBulkStateAsync should have typed overload that performs bulk deserialization
## Describe the feature
When calling `DaprClient.GetStateAsync<T>` one can specify a type parameter to have the SDK deserialize the response to. This is nice as it prevents the user from having to maintain their own serialization/deserialization options somewhere and rely on whatever the SDK is configured to use.

However, when using `DaprClient.GetBulkStateAsync`, this does not accept a type parameter, so one ultimately retrieves an `IReadOnlyList<BulkStateItem>` wherein the `BulkStateItem` contains ETag, Key and Value strings. This leaves deserialization to the user (who again, may have relied on Dapr to perform the initial serialization and thus may not be clued into precisely how it's serialized).

I would propose that for historical reasons, the existing approach be maintained, but that an overload be added to both `GetBulkStateAsync` and `BulkStateItem` that each accept a type parameter and which deserialize the returned result from the former as `IReadOnlyList<BulkStateItem<T>>` wherein the `BulkStateItem` contains a string property for both Key and ETag, but a type T value, wherein deserialization has already been performed, like that of `GetStateAsync`.

## Release Note
A type parameter overload has been added to `BulkStateItem` so items retrieved from state using `GetBulkStateItem<T>` will now have their values deserialize to T instead of exclusively returning a serailized string.

<!-- RELEASE NOTE: **ADD** New feature in Dapr. -->
<!-- RELEASE NOTE: **FIX** Bug in runtime. -->
<!-- RELEASE NOTE: **UPDATE** Runtime dependency. -->

RELEASE NOTE:
**ADD** A type parameter overload has been added to `BulkStateItem` so the value of items retrieved from state using `GetBulkStateItem<T>` will now deserialize to T instead of exclusively returning a serialized string.
