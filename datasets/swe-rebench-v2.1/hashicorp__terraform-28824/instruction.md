Trying to apply a stale TF plan does not remove state locks (0.15)
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
+ provider registry.terraform.io/hashicorp/azurerm v2.58.0
+ provider registry.terraform.io/hashicorp/google v3.64.0
+ provider registry.terraform.io/hashicorp/google-beta v3.64.0
```

### Terraform Configuration Files
<!--
Paste the relevant parts of your Terraform configuration between the ``` marks below.

For Terraform configs larger than a few resources, or that involve multiple files, please make a GitHub repository that we can clone, rather than copy-pasting multiple files in here. For security, you can also encrypt the files using our GPG public key at https://www.hashicorp.com/security.
-->

```terraform
terraform {
  backend "gcs" {
    bucket = "bucket"
    prefix = "/path/terraform.tfstate"
  }
}

resource "null_resource" "test_unlock" {
}
```

### Debug Output
<!--
Full debug output can be obtained by running Terraform with the environment variable `TF_LOG=trace`. Please create a GitHub Gist containing the debug output. Please do _not_ paste the debug output in the issue, since debug output is long.

Debug output may contain sensitive information. Please review it before posting publicly, and if you are concerned feel free to encrypt the files using the HashiCorp security public key.
-->
https://gist.github.com/pmjacinto/96e79029d10ccdaf944d42fd0ddaee46

### Crash Output
<!--
If the console output indicates that Terraform crashed, please share a link to a GitHub Gist containing the output of the `crash.log` file.
-->
N/A

### Expected Behavior
<!--
What should have happened?
-->
The second terraform apply shouldn't have left a lock.

### Actual Behavior
<!--
What actually happened?
-->
The second terraform apply left a lock.

### Steps to Reproduce
<!--
Please list the full steps required to reproduce the issue, for example:
1. `terraform init`
2. `terraform apply`
-->
1. `terraform init`
2. `terraform plan -out plan.tfplan`
3. `terraform apply plan.tfplan` (create null resource)
4. `terraform apply plan.tfplan` (apply again to get the stale message -> does not remove the lock)
5. `terraform apply plan.tfplan` (to confirm that is locked)

### Additional Context
<!--
Are there anything atypical about your situation that we should know? For example: is Terraform running in a wrapper script or in a CI system? Are you passing any unusual command line options or environment variables to opt-in to non-default behavior?
-->
Didn't test with pre 0.15 but we've started experiencing these after the upgrade.

### References
<!--
Are there any other GitHub issues (open or closed) or Pull Requests that should be linked here? For example:

- #6017

-->

### Additional contract requirements

The stale-plan behaviour is observed through the local backend's public method `(*Local).Context(op *backend.Operation) (*terraform.Context, statemgr.Full, tfdiags.Diagnostics)` in `internal/backend/local`. When the plan file carried by the operation is stale relative to the current state, this method returns diagnostics that contain an error and releases the state lock it holds for the operation.
