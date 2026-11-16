libregraph: PATCH/GET/DELETE with school `id` or `schoolNumber`
We want to treat `schoolNumber` as the unique property, similar to the `userPrincipalName`. Then all request types should allow using the `schoolNumber` or the school `id`: `/education/schools/{id | schoolNumber}`

### Additional contract requirements

- `PatchEducationSchool` (PATCH `/education/schools/{id | schoolNumber}`) responds to a successful update with HTTP `200 OK` and the updated school representation in the response body.
- A PATCH request against a read-only LDAP backend must be rejected without changing the school.
