Importing aiven_pg_user forces recreation after fork and restore
## What happened?

I created a new database service using the [aiven_pg](https://registry.terraform.io/providers/aiven/aiven/latest/docs/resources/pg) resource and the `pg_service_to_fork_from`-property.

After creating the service, I wanted to import all databases, connection pools and users into my IaC/terraform-state. Importing databases and connection pools worked as expected, but after importing users I got a diff when running `terraform plan` (names have been changed):

```
terraform: -/+ destroy and then create replacement
14:54:17.306 STDOUT terraform: Terraform will perform the following actions:
14:54:17.306 STDOUT terraform:   # aiven_pg_user.foo["my-server_my-user"] must be replaced
14:54:17.306 STDOUT terraform: -/+ resource "aiven_pg_user" "foo" {
14:54:17.306 STDOUT terraform:       + access_cert          = (sensitive value)
14:54:17.306 STDOUT terraform:       + access_key           = (sensitive value)
14:54:17.306 STDOUT terraform:       ~ id                   = "my-project/my-service/my-user -> (known after apply)
14:54:17.307 STDOUT terraform:       ~ password             = (sensitive value)
14:54:17.307 STDOUT terraform:       - pg_allow_replication = false -> null
14:54:17.307 STDOUT terraform:       + project              = "my-project" # forces replacement
14:54:17.307 STDOUT terraform:       + service_name         = "my-service" # forces replacement
14:54:17.307 STDOUT terraform:       ~ type                 = "normal" -> (known after apply)
14:54:17.307 STDOUT terraform:         # (1 unchanged attribute hidden)
14:54:17.307 STDOUT terraform:     }
14:54:17.307 STDOUT terraform: Plan: 1 to add, 0 to change, 1 to destroy.
```

Just to be sure, I also tested this with clickopsing (using the "fork & restore"-feature), with the same result.

As you can see from the diff, it seems like the `project` and `service_name` properties are not included in the imported resource, forcing replacement.

## What did you expect to happen?

No diff after import. At least the required properties for `aiven_pg_user`, like the ones missing here, should be present.

## What else do we need to know?

Terraform v1.10.5
on darwin_arm64
+ provider registry.terraform.io/aiven/aiven v4.36.0
