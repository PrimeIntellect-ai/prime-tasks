Deprecate plugin_version functionality
## Describe the bug

Currently, the OpenAPI Terraform config file enables the user to specify the `plugin_version` as a way to ensure the config is targeted towards a specific version of the OpenAPI plugin binary. This was a feature added in early stages of the provider as a security mechanism to validate that the expected version of the binary was being used or fail close at runtime otherwise. This mechanism is no longer working as intended causing issues for users when they have different Terraform configurations each pointing at different versions of the OpenAPI Terraform provider but yet the global OpenAPI Terraform plugin configuration is set with one specific version.

## To Reproduce

Steps to reproduce the behavior:
1. Define the OpenAPI Terraform config file as defined in the [OpenAPI plugin configuration schema](https://github.com/dikhan/terraform-provider-openapi/blob/master/docs/plugin_configuration_schema.md)

````
version: '1'
services:
  swaggercodegen:
    swagger-url: https://swaggercodegen-service-provider-api.com/swagger.yaml
    plugin_version: 2.2.0
````

2. Install two different versions of the plugin using the script (pretending the following commands were executed in different points in time and therefore different versions of the provider got installed):

````
$ ./scripts/install.sh --provider-name exampleprovider --provider-source-address "terraform.example.com/examplecorp"
Terraform provider successfully installed!
 |--> Installation Path: /Users/user/.terraform.d/plugins/terraform.example.com/examplecorp/exampleprovider/2.1.0/darwin_amd64/terraform-provider-exampleprovider
$ ./scripts/install.sh --provider-name exampleprovider --provider-source-address "terraform.example.com/examplecorp"
Terraform provider successfully installed!
 |--> Installation Path: /Users/user/.terraform.d/plugins/terraform.example.com/examplecorp/exampleprovider/2.2.0/darwin_amd64/terraform-provider-exampleprovider
````

3. Create a terraform project defining resources for the `exampleprovider` and locking the provider version to `2.1.0`:

- main.tf
````
terraform {
  required_providers {
    swaggercodegen = {
      source  = "terraform.example.com/examplecorp/exampleprovider"
      version = "2.1.0"
    }
  }
}

resource "exampleprovider_some_resouce" "my_resource" {
...
}
````

- Running terraform plan will fail with the following error:

````
$ terraform plan
....
2021/09/29 19:23:38 [ERROR] error initialising the terraform provider: plugin init error: service configuration for 'exampleprovider' not valid: plugin version '2.2.0' in the plugin configuration file does not match the version of the OpenAPI plugin that is running '2.1.0'
````

## Expected behaviour

The `plugin_version` should be ignored since Terraform supports installing multiple versions of the same plugin and then locking the versions in the terraform configurations as desired. The `plugin_version` functionality prevents users from being able to use different versions of the provider at the moment.

Example:
```gherkin
Scenario: plugin_version functionality is no longer exercised
Given an OpenAPI Terraform configuration that explicitly specifies the plugin_version
When the provider is called by Terraform
Then even though the binary may not match the plugin version specified in the config file the provider should not fail and work as expected. The validation for the plugin_version match in the provider should be ignored completely and any code related to that deprecated (including the documentation)
```

## Additional context
Add any other context about the problem here.

### Checklist (for admin only)

**Don't forget to go through the checklist to make sure the issue is created properly**:

- [x] I have added a corresponding label (bug) to the issue (right side menu)
- [x] I have added this issue to the 'API Terraform Provider' GitHub project (right side menu)
