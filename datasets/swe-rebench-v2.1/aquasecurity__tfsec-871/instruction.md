AWS018 failures
**Describe the bug**
TFsec is failing with AWS018

```
Resource 'aws_security_group_rule.untrust-rules' should include a non-empty description for auditing purposes.
```

Terraform
```
resource "aws_security_group_rule" "trust-rules-dev" {
  count = ...
  description       = var.trust-sg-rules[count.index]["description"]
...

variable "trust-sg-rules" {
  description = "A list of maps that creates a number of security group rules for the trust interface"
  type        = list(map(string))
...
```
Version 0.45.0

What am I doing wrong?
