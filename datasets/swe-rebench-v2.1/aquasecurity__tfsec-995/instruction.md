For Each aws-s3-specify-public-access-block incorrectly failed
**Describe the bug**

aws-s3-specify-public-access-block shows erroneous violation if using with for_each blocks.

**To Reproduce**
Steps to reproduce the behavior:

```tf
resource "aws_s3_bucket" "example" {
  for_each      = toset(["example1", "example2"])
  bucket        = each.key
  .....
}

resource "aws_s3_bucket_public_access_block" "example" {
  for_each = aws_s3_bucket.example
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
}
```
This code will fail the rule listed, despite defining an aws_s3_bucket_public_access_block

**Expected behavior**
The rule should pass if aws_s3_bucket_public_access_block includes a for_each that references the bucket

**Info**

- OS: mac Big Sur (11.5)
- tfsec:
```shell
tfsec --version
0.55.1
```
