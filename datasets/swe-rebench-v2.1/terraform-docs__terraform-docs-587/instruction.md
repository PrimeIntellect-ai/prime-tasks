Inconsinstent markdown generation when using heredoc in terraform output (CRLF vs LF)
<!--
Thank you for helping to improve terraform-docs!

Please be sure to search for open issues before raising a new one. We use issues
for bug reports and feature requests. Please note, this template is for bugs
report, not feature requests. For more information, see the Contributing Guidelines
at https://git.io/JtEzg. Please find us at https://slack.terraform-docs.io/ for
questions, support, and discussion.
-->

### Describe the bug

<!--
Please let us know what behaviour you expected and how terraform-docs diverged
from that behaviour.
-->

Inconsistent markdown generation when using multi-line strings (heredoc) in outputs, currently dependant on the line ending.

When using with Windows line ending(CRLF) in outputs, it makes the markdown output multiline, but when using linux line ending, it generates a single line.

I think that this problem is related to https://github.com/terraform-docs/terraform-docs/issues/305. Maybe the fix should be applied to the outputs too?

### How can we reproduce it?

1. Create a `main.tf` with this content and save it with Windows line endings (CRLF):
```hcl
output "example" {
  value       = "this is an example"
  description = <<EOT
Lorem ipsum dolor sit amet,
consectetur adipiscing elit,
sed do eiusmod tempor incididunt
ut labore et dolore magna aliqua.
Ut enim ad minim veniam,
quis nostrud exercitation ullamco
laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate
velit esse cillum dolore eu fugiat nulla pariatur.
Excepteur sint occaecat cupidatat non proident,
sunt in culpa qui officia deserunt mollit anim id est laborum.
EOT
  sensitive   = false
}

```

2. Run `terraform-docs markdown .`
```md
## Requirements

No requirements.

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_example"></a> [example](#output\_example) | Lorem ipsum dolor sit amet,
<br>consectetur adipiscing elit,
<br>sed do eiusmod tempor incididunt
<br>ut labore et dolore magna aliqua.
<br>Ut enim ad minim veniam,
<br>quis nostrud exercitation ullamco
<br>laboris nisi ut aliquip ex ea commodo consequat.
<br>Duis aute irure dolor in reprehenderit in voluptate
<br>velit esse cillum dolore eu fugiat nulla pariatur.
<br>Excepteur sint occaecat cupidatat non proident,
<br>sunt in culpa qui officia deserunt mollit anim id est laborum. |

```
3. Now, replace the `main.tf` line endings to the linux type (LF) and re-run the command `terraform-docs markdown .`
```md
## Requirements

No requirements.

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_example"></a> [example](#output\_example) | Lorem ipsum dolor sit amet, <br>consectetur adipiscing elit, <br>sed do eiusmod tempor incididunt <br>ut labore et dolore magna aliqua. <br>Ut enim ad minim veniam, <br>quis nostrud exercitation ullamco <br>laboris nisi ut aliquip ex ea commodo consequat. <br>Duis aute irure dolor in reprehenderit in voluptate <br>velit esse cillum dolore eu fugiat nulla pariatur. <br>Excepteur sint occaecat cupidatat non proident, <br>sunt in culpa qui officia deserunt mollit anim id est laborum. |

```

<!--
Help us to reproduce your bug as succinctly and precisely as possible. Any and
all steps or script that triggers the issue are highly appreciated!

Do you have long logs to share? Please go to https://ghostbin.com and insert the
link here.
-->


### Environment information
- terraform-docs version: tested on v0.12.1 and 0.16.0
- OS: Windows 10
