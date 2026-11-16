terraform: support for child modules
According to the [Terraform JSON output format](https://www.terraform.io/docs/internals/json-format.html#values-representation) any module (including the root module) may contain child modules that describe their own resources. The module tree is described recursively.

Currently, no module other than the root module will be estimated as the `child_modules` property is ignored by the Terraform plan reader.
