Check for descriptions in ingress and egress blocks within aws_security_group resources
**Is your feature request related to a problem? Please describe.**
We would like to ensure `ingress` and (optionally) `egress` blocks within `aws_security_group` resources have a `description` field. Right now, AWS018 seems to only inspect `aws_security_group_rule` resources, or descriptions at the top level of `aws_security_group`.

**Describe alternatives you've considered**
We're using a custom check to accomplish this, but it would be nice to have the functionality in a core rule.

**Additional context**

In this example, we'd like to detect the missing description from the second `ingress` block:

```
resource "aws_security_group" "example" {
  name        = "example"
  description = "Some SG" # we don't care about this
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "access from xyz" # this description is the important one
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.foo.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.foo.id]
  }
}
```

### Additional contract requirements

Both `ingress` and `egress` blocks within `aws_security_group` resources must be checked. Any `ingress` or `egress` block that does not declare a `description` (or declares an empty one) must produce a finding for the `aws-vpc-add-description-to-security-group` check, even when other blocks in the same resource do declare a description.
