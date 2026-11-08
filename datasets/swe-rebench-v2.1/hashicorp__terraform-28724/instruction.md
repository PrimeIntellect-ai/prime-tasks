Terraform does not show error messages for failed resource operations if it also fails to save the state to backend
<!--
Hi there,

Thank you for opening an issue. Please note that we try to keep the Terraform issue tracker reserved for bug reports and feature requests. For general usage questions, please see: https://www.terraform.io/community.html.

If your issue relates to a specific Terraform provider, please open it in the provider's own repository. The index of providers is at https://github.com/terraform-providers.

To fix problems, we need clear reproduction cases - we need to be able to see it happen locally. A reproduction case is ideally something a Terraform Core engineer can git-clone or copy-paste and run immediately, without inventing any details or context.

* A short example can be directly copy-pasteable; longer examples should be in separate git repositories, especially if multiple files are needed
* Please include all needed context. For example, if you figured out that an expression can cause a crash, put the expression in a variable definition or a resource
* Set defaults on (or omit) any variables. The person reproducing it should not need to invent variable settings
* If multiple steps are required, such as running terraform twice, consider scripting it in a simple shell script. For example, see [this case](https://github.com/danieldreier/terraform-issue-reproductions/tree/master/25719). Providing a script can be easier than explaining what changes to make to the config between runs.
* Omit any unneeded complexity: remove variables, conditional statements, functions, modules, providers, and resources that are not needed to trigger the bug
* When possible, use the [null resource](https://www.terraform.io/docs/providers/null/resource.html) provider rather than a real provider in order to minimize external dependencies. We know this isn't always feasible. The Terraform Core team doesn't have deep domain knowledge in every provider, or access to every cloud platform for reproduction cases.

-->

### Terraform Version
<!---
Run `terraform version` to show the version, and paste the result between the ``` marks below.

If you are not running the latest version of Terraform, please try upgrading because your issue may have already been fixed.
-->

```
Terraform v0.15.3
on darwin_amd64
+ provider registry.terraform.io/hashicorp/aws v3.40.0
```

### Terraform Configuration Files
<!--
Paste the relevant parts of your Terraform configuration between the ``` marks below.

For Terraform configs larger than a few resources, or that involve multiple files, please make a GitHub repository that we can clone, rather than copy-pasting multiple files in here. For security, you can also encrypt the files using our GPG public key at https://www.hashicorp.com/security.
-->

```terraform
terraform {
  backend "s3" {
    bucket = "my-tfstate-bucket"
    key    = "terraform/backend-error-bug"
    region = "us-west-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

# Non-unique bucket name, this will fail to Create
resource "aws_s3_bucket" "a" {
  bucket = "my-tf-test-bucket"
  acl    = "private"
}

# Unique bucket name will Create successfully
resource "aws_s3_bucket" "b" {
  bucket = "my-tf-test-bucket-randombits"
  acl    = "private"
}

```

### Debug Output
<!--
Full debug output can be obtained by running Terraform with the environment variable `TF_LOG=trace`. Please create a GitHub Gist containing the debug output. Please do _not_ paste the debug output in the issue, since debug output is long.

Debug output may contain sensitive information. Please review it before posting publicly, and if you are concerned feel free to encrypt the files using the HashiCorp security public key.
-->
https://gist.github.com/CyrusJavan/89b025bdbc55f095625c537d8cfa97aa (Encrypted with HashiCorp Public Key)

### Expected Behavior
<!--
What should have happened?
-->
Within the same `terraform apply` if there are resource operation failures and backend state saving failures, all error messages should be output to the user.
### Actual Behavior
<!--
What actually happened?
-->
Only the backend state saving error was output to the user, the resource failures failed silently.
![image](https://user-images.githubusercontent.com/8885202/118329814-ecd1f980-b4bb-11eb-8037-bcf882b7550b.png)

### Steps to Reproduce
<!--
Please list the full steps required to reproduce the issue, for example:
1. `terraform init`
2. `terraform apply`
-->
0. Configure credentials separate credentials for the S3 backend and the aws provider
1. `terraform init`
2. `terraform apply` DO NOT TYPE 'yes' YET
3.  Go to https://console.aws.amazon.com/iam/home#/security_credentials and deactivate the creds you are using for the S3 backend.
4. Type 'yes' and continue the apply
5. Error is shown for failing to save state, but the error from creating the bucket with a non-unique name is not shown.

### Additional Context
<!--
Are there anything atypical about your situation that we should know? For example: is Terraform running in a wrapper script or in a CI system? Are you passing any unusual command line options or environment variables to opt-in to non-default behavior?
-->
Deactivating the credentials midway through the apply is just a way to reproduce easily, this actually happened in production from a very long apply (+2 hours) and the token had expired by the time we reached the end of the apply.

### Additional contract requirements

- For this backend-save failure case, the fallback `errored.tfstate` must include the line `test_instance.foo: (tainted)`.
