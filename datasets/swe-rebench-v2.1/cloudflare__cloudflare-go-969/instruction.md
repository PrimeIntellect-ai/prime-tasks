Missing Add Custom Domain to CF Pages
### Current cloudflare-go version

latest

### Description

I cant find the Add a custom Domain for CF Pages.
It seems also missing in the API Reference, but the Endpoint seems to work:
https://community.cloudflare.com/t/add-pages-domain-via-api/303510/4

Updating and Deleting would be awesome too

### Use cases

It would be really awesome to add custom domains.

### Potential cloudflare-go usage

```go
api.CreatePagesDomain(...)
```


### References

_No response_

### Additional contract requirements

Add support for Cloudflare Pages custom domains through the following public API in package `cloudflare`:

- Type `PagesDomain` with string fields `ID`, `Name`, `Status`, and `ZoneTag`, a `VerificationData` field of type `VerificationData`, a `ValidationData` field of type `ValidationData`, and a `CreatedOn` field of type `*time.Time`.
- Type `VerificationData` with a string field `Status`.
- Type `ValidationData` with string fields `Status` and `Method`.
- Type `PagesDomainsParameters` with string fields `AccountID` and `ProjectName`.
- Type `PagesDomainParameters` with string fields `AccountID`, `ProjectName`, and `DomainName`.
- Method `API.GetPagesDomains(ctx context.Context, params PagesDomainsParameters) ([]PagesDomain, error)` that retrieves all custom domains for a Pages project. It returns `ErrMissingAccountID` when `AccountID` is empty and `ErrMissingProjectName` when `ProjectName` is empty.
- Method `API.GetPagesDomain(ctx context.Context, params PagesDomainParameters) (PagesDomain, error)` that retrieves a single custom domain. It returns `ErrMissingAccountID`, `ErrMissingProjectName`, or `ErrMissingDomain` when the corresponding parameter is empty.
- Method `API.PagesPatchDomain(ctx context.Context, params PagesDomainParameters) (PagesDomain, error)` that retriggers validation for a custom domain. It returns `ErrMissingAccountID`, `ErrMissingProjectName`, or `ErrMissingDomain` when the corresponding parameter is empty.
- Method `API.PagesAddDomain(ctx context.Context, params PagesDomainParameters) (PagesDomain, error)` that adds a custom domain. It returns `ErrMissingAccountID`, `ErrMissingProjectName`, or `ErrMissingDomain` when the corresponding parameter is empty.
- Method `API.PagesDeleteDomain(ctx context.Context, params PagesDomainParameters) error` that removes a custom domain. It returns `ErrMissingAccountID`, `ErrMissingProjectName`, or `ErrMissingDomain` when the corresponding parameter is empty.

Each method must honour the supplied `ctx` for cancellation and timeout.

The requests target the following endpoints:

- `GET /accounts/{AccountID}/pages/projects/{ProjectName}/domains` to list the domains of a project.
- `GET /accounts/{AccountID}/pages/projects/{ProjectName}/domains/{DomainName}` to fetch a single domain.
- `POST /accounts/{AccountID}/pages/projects/{ProjectName}/domains` to add a domain.
- `PATCH /accounts/{AccountID}/pages/projects/{ProjectName}/domains/{DomainName}` to retrigger validation for a domain.
- `DELETE /accounts/{AccountID}/pages/projects/{ProjectName}/domains/{DomainName}` to delete a domain.
