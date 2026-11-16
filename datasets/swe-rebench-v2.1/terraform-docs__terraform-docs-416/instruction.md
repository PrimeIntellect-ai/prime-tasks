Option to not include the Type and Default values of the variables in the generated documents.
<!-- Please note, this template is for feature requests, not bugs report -->
<!-- For more information, see the Contributing Guidelines at -->
<!-- https://github.com/terraform-docs/terraform-docs/tree/master/CONTRIBUTING.md -->

**Is your feature request related to a problem? Please describe.**

In my `variables.tf` file I only have variable definitions, all of the variables I use are of type `string` and none of them have default values as I pass my values to Terraform's CLI using different `.tfvars` files per-environment (ex. `prod.tfvars`, `dev.tfvars`) therefore, when I generate my documents I have two columns that say the exact same thing for all my rows:

| Type | Default |
|-|-|
| `string` | n/a |

**Describe the solution you'd like**

I'd like a configuration option that would allow me to set the value of those variables to `false` so they don't get included in my documentation, something similar to what we can achieve with `required: false` but for `Type` and `Default` so I could add to my `.terraform-docs.yml` something like this:

```yaml
settings:
  required: false
  default: false
  type: false
```

**Describe alternatives you've considered**

1. Removing that column manually.
2. Using a shell script to remove that column automatically.

**Additional context**

Here's a screenshot of how those the `Type` and `Default` columns look:

![Screen Shot 2020-08-26 at 17 54 28](https://user-images.githubusercontent.com/10160626/91364832-3d39e780-e7c5-11ea-8eb7-8369e2df6fd0.png)

And thanks a lot for maintaining this project!

### Additional contract requirements

The `settings.default` and `settings.type` configuration booleans control whether variable Default and Type information is shown, independently of one another. Both are shown unless their corresponding option is set to `false`.
