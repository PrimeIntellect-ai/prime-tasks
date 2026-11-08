Add support for deleting an organization.
A new REST endpoint was added to delete an organization at `/orgs/{org}'`. The documentation doesn't seem to have gone live quite yet but I'll update the issue as soon as I see it. In the meantime the endpoint can be evoked like:

`curl -X DELETE https://api.github.com/orgs/:org`

Now with [documentation](https://docs.github.com/en/rest/orgs/orgs?apiVersion=2022-11-28#delete-an-organization)!

### Additional contract requirements

- Expose organization deletion as `OrganizationsService.Delete(ctx context.Context, org string) (*Response, error)`. It accepts a request context and organization name and sends a DELETE request to `/orgs/{org}` to permanently remove the specified organization. The request is subject to the supplied context: if that context is already canceled, the call returns an error for which `errors.Is(err, context.Canceled)` holds.
