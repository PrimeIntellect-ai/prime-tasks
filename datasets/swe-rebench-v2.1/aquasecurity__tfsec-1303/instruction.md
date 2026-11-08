AWS Elasticsearch - convert tfsec checks to use defsec logic
Adapt AWS Elasticsearch Domains to Go structs based on #1194 instructions:

Remove tfsec logic from `internal/app/tfsec/rules/aws/elasticsearch/enable_domain_encryption_rule.go`
`internal/app/tfsec/rules/aws/elasticsearch/enable_domain_logging_rule.go`
`internal/app/tfsec/rules/aws/elasticsearch/enable_in_transit_encryption_rule.go`
`internal/app/tfsec/rules/aws/elasticsearch/enforce_https_rule.go`
`internal/app/tfsec/rules/aws/elasticsearch/use_secure_tls_policy_rule.go`

Create adapt functions to populate the Go structs in `internal/app/tfsec/adapter/aws/elasticsearch/adapt.go`
