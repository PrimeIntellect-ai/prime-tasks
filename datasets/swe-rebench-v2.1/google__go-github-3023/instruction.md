Bug in CreateOrUpdateRepoCustomPropertyValues?
We are looking to replace our custom-built methods for listing and updating custom property values, with the methods provided in v57.

It seems the CreateOrUpdateRepoCustomPropertyValues method has a bug however. We haven't actually tested it yet, but [HIDDEN]

```go
// Wrong type in last arg?
func (s *OrganizationsService) CreateOrUpdateRepoCustomPropertyValues(ctx context.Context, org string, repoNames []string, [HIDDEN]) (*Response, error) {
	u := fmt.Sprintf("orgs/%v/properties/values", org)

	params := struct {
		RepositoryNames []string          `json:"repository_names"`
		[HIDDEN]
	}{
		RepositoryNames: repoNames,
		Properties:      properties,
	}

	req, err := s.client.NewRequest("PATCH", u, params)
	if err != nil {
		return nil, err
	}

	return s.client.Do(ctx, req, nil)
}
```

### Additional contract requirements

- `CreateOrUpdateRepoCustomPropertyValues` must accept `properties []*CustomPropertyValue` and send each property's name and `value` in the PATCH request payload.
- The update must be sent as an HTTP PATCH to the organization's custom property values endpoint, `/orgs/{org}/properties/values`.
