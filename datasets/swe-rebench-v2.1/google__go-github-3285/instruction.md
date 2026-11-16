feat: Support getting an organization role
Support getting an organization role. [Docs here](https://docs.github.com/en/enterprise-cloud@latest/rest/orgs/organization-roles?apiVersion=2022-11-28#get-an-organization-role)

I can also work on this

### Additional contract requirements

- On a successful `OrganizationsService.GetOrgRole` call, the returned `*Response` is non-nil and its `StatusCode` is `200` (`http.StatusOK`).
