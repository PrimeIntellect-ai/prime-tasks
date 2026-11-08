Support additional GitHub pages update parameters
The https://pkg.go.dev/github.com/google/go-github/v41/github#RepositoriesService.UpdatePages API only currently supports updating the CNAME and source properties: https://github.com/google/go-github/blob/178169fc04bc4a05ca48f98709cdd02ab5b556e3/github/repos_pages.go#L90-L98

There are additional parameters which would be useful for consumers (i.e. terraform provider) to be able to update (see https://docs.github.com/en/rest/reference/pages#update-information-about-a-github-pages-site for reference):
* https_enforced
* public

### Additional contract requirements

- The `PagesUpdate` type in package `github` must expose two additional optional fields: `Public *bool` and `HTTPSEnforced *bool`.
- When a `PagesUpdate` value is used to update a GitHub Pages site, the `Public` field must be sent under the JSON key `public` and the `HTTPSEnforced` field under the JSON key `https_enforced`.
- `PagesUpdate` must provide a method `GetPublic() bool` that returns the value of the `Public` field when the receiver and the field are non-nil, and `false` otherwise (including a nil receiver).
- `PagesUpdate` must provide a method `GetHTTPSEnforced() bool` that returns the value of the `HTTPSEnforced` field when the receiver and the field are non-nil, and `false` otherwise (including a nil receiver).
