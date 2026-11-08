AWS-098 dosen't recognize public_access_block when count is used
**Describe the bug**
When using a count to conditionally create a s3 bucket, AWS-098 is triggered even when a public_access_block is associated with the bucket

**To Reproduce**
```
resource "aws_s3_bucket" "access-logs-bucket" {
  count = var.enable_cloudtrail ? 1 : 0
  bucket = "cloudtrail-access-logs"
  acl    = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "access-logs" {
  count = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.access-logs-bucket[0].id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}
```

**Expected behavior**
No warnings, since the bucket has a public_access_block associated with it.
