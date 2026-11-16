Regression with conditional resources
Something changed recently which caused projects using the [terraform-aws-vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc/) module to be flagged because it conditionally manages the default VPC. This rule will trigger even with the default value (0).

```
 [AWS082][ERROR] Resource 'module.vpc:aws_default_vpc.this' should not exist
  /Users/…/.terraform/modules/vpc/main.tf:1301-1315


    1298 | # Defaults
    1299 | ################################################################################
    1300 |
    1301 | resource "aws_default_vpc" "this" {
    1302 |   count = var.manage_default_vpc ? 1 : 0
    1303 |
    1304 |   enable_dns_support   = var.default_vpc_enable_dns_support
    1305 |   enable_dns_hostnames = var.default_vpc_enable_dns_hostnames
    1306 |   enable_classiclink   = var.default_vpc_enable_classiclink
    1307 |
    1308 |   tags = merge(
    1309 |     {
    1310 |       "Name" = format("%s", var.default_vpc_name)
    1311 |     },
    1312 |     var.tags,
    1313 |     var.default_vpc_tags,
    1314 |   )
    1315 | }
    1316 |
```

Version: tfsec 0.45.8
