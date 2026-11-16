Expose `provider` and `type` for estimated resources
The `cost.Resource` and `cost.ResourceDiff` structs are missing any information about which provider they belong to and which type they are. Currently, the only way to extract this is from the address, however, this is being complicated by the fact that module resource addresses are different from root module ones and also by the effort that library consumers would require.

These two fields would be much better provided by us on the aforementioned types.

### Additional contract requirements

- The `terraform.Provider` interface exposes a `Name() string` method that returns the provider's common name.
- The `query.Resource` struct exposes `Provider string` and `Type string` fields. Extracted planned and prior queries set `Provider` to the provider's name and `Type` to the Terraform resource type (for example, `aws_instance`).
- The `cost.Resource` struct exposes `Provider string` and `Type string` fields, carrying the provider name and resource type of the resource.
- The `cost.ResourceDiff` struct exposes `Provider string` and `Type string` fields, carrying the provider name and resource type of the resource it describes.
