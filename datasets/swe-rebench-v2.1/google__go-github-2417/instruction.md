List User Migrations: Add support for pagination
The [ListUserMigrations()](https://github.com/google/go-github/blob/3a432d62bf0318c14b2d1d7415bf94ea1a884342/github/migrations_user.go#L100) currently doesn't support pagination options.

We should add it.

PS: Will be creating a pull request shortly.

### Additional contract requirements

- `MigrationService.ListUserMigrations` in package `github` must accept pagination options, with the signature `ListUserMigrations(ctx context.Context, opts *ListOptions) ([]*UserMigration, *Response, error)`.
- When pagination options are supplied, the corresponding `page` and `per_page` query parameters must be included in the request.
