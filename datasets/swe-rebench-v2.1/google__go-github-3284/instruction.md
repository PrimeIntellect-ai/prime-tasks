feat: Support creating an organization role with base role
When creating an organizational role you can grant it repo level permissions. When you do that you also have to give it a base role to inherit permissions from.

[Docs](https://docs.github.com/en/enterprise-cloud@latest/rest/orgs/organization-roles?apiVersion=2022-11-28#create-a-custom-organization-role)

I can work on this

### Additional contract requirements

- `CreateOrUpdateOrgRoleOptions` (package `github`) exposes a public field `BaseRole` of type `*string`. When set, it is sent as the `base_role` property of the JSON request body used to create a custom organization role.
- `CreateOrUpdateOrgRoleOptions` exposes a method `GetBaseRole() string` that returns the value of `BaseRole`, or the empty string when the receiver or the field is nil.
