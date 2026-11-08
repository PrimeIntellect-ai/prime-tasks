Using heredoc with CRLF encoding breaks markdown output
<!-- Please note, this template is for bugs report, not feature requests -->
<!-- For more information, see the Contributing Guidelines at -->
<!-- https://github.com/terraform-docs/terraform-docs/tree/master/CONTRIBUTING.md -->

**Describe the bug**

Using multi-line strings (heredoc) with Windows line encoding (CRLF) breaks markdown output.

**To Reproduce**

Steps to reproduce the behavior:

1. Create `main.tf` and save it with Windows line encoding (CRLF)

```hcl
variable "myvar" {
    type = string
    description = <<-EOT
    The quick brown fox jumps
    over the lazy dog
    EOT
}
```

2. `terraform-docs --no-outputs --no-requirements --no-providers md .`


```
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
<br>over the lazy dog | `string` | n/a | yes |
```

**Expected behavior**

The markdown output should contain the full description

```
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| myvar | The quick brown fox jumps<br>over the lazy dog | `string` | n/a | yes |
```

**Version information:**

- terraform-docs version: `v0.0.0- v0.9.1 darwin/amd64 BuildDate: 2020-04-02T23:00:25+0100`
- OS: `MacOS`

**Additional context**

Saving the `main.tf` file with UNIX line encoding (LF) creates the desired markdown.
