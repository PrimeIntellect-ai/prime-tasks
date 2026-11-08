Add domain name validation to Python Connector
Add regex to validate domain name used is in proper format.

Similar to how we validate an instance connection name:

https://github.com/GoogleCloudPlatform/cloud-sql-python-connector/blob/fb8c21c89af524bdd00c51eeb0bcb4a6bf4dbbd3/google/cloud/sql/connector/connection_name.py#L46-L54

Below is what we used in Go Connector:

```go
// The domain name pattern in accordance with RFC 1035, RFC 1123 and RFC 2181.
domainNameRegex = regexp.MustCompile([HIDDEN])
```

Can use Go as ref: https://github.com/GoogleCloudPlatform/cloud-sql-go-connector/pull/925

### Additional contract requirements

For DNS-based connection lookup, a malformed domain name must be rejected without attempting DNS resolution. A domain must have at least one dot. Labels are at most 63 characters. Labels before the optional last label begin with a lowercase ASCII letter, digit, or underscore; they may contain lowercase ASCII letters, digits, underscores, and hyphens, and must end with a lowercase ASCII letter or digit. A nonempty last label begins with a lowercase ASCII letter, may then contain lowercase ASCII letters, digits, and hyphens, and must end with a lowercase ASCII letter or digit. A single trailing dot is accepted.
