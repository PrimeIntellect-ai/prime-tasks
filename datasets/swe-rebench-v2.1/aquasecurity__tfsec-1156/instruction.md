Ignore checks with variable context
**Is your feature request related to a problem? Please describe.**
Hey! I have complex TF code with dynamic resources based on variables. Trying to use tfsec and it works great! Thank you!

But I want to skip some checks for part of variable and haven't seen possibility to do this.

example:
```
locals {
  rules = {
    http = 80
    https = 443
  }
}

resource "aws_security_group_rule" "this" {
      for_each = local.rules
      type = "ingress"
      description     = "test"
      from_port       = each.value
      to_port         = each.value
      protocol        = "tcp"
      cidr_blocks     = ["0.0.0.0/0"]

}
```

the aim is ignore `aws-vpc-no-public-ingress-sgr` for port 443, but still have an error for port 80

**Describe the solution you'd like**
Ignore checks for parts of variables

```
locals {
  rules = {
    http = 80
    #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    https = 443
  }
}
```

**Describe alternatives you've considered**
A clear and concise description of any alternative solutions or features you've considered.

**Additional context**
Some kind related to https://github.com/aquasecurity/tfsec/issues/493

### Additional contract requirements

The value-scoped ignore is expressed as a resource-level ignore comment with bracket selectors appended to the rule id:

```
#tfsec:ignore:<rule-id>[<attribute>=<value>,...]
```

- The ignore comment must be attached to the resource block that produces the finding. A comment placed on an individual variable map entry is not a supported mechanism for value-scoped ignores.
- A selector `<attribute>=<value>` matches when the resource block has an attribute named `<attribute>` whose value equals `<value>`. Numeric attribute values are compared as integers (for example `from_port=443`), and string attribute values are compared as strings.
- The finding is suppressed only when at least one selector matches; if no selector matches, the finding is still reported.
- A malformed selector does not suppress the finding. For example, `[from_port=abc]` (a non-numeric value for a numeric attribute) and `[from_portabc]` (no `=`) leave the finding reported.
- Multiple selectors may be combined with commas, for example `[from_port=443,to_port=80]`; the finding is suppressed when any one of them matches.
