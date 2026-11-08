Add missing apps methods
Currently, only a subset of the GitHub Apps API is supported: https://github.com/google/go-github/blob/master/github/apps.go

Compare with: https://developer.github.com/v3/apps/

(As a side note, [the spreadsheet ](https://docs.google.com/spreadsheets/d/1wlHnoJSAN01nXUUF1JobsaKO4mJjAwZNWK8L_4ZSlls/edit#gid=0) doesn't mention the apps API at all.)

### Additional contract requirements

- `Get` must retrieve the authenticated app when the slug is empty and the app identified by a nonempty slug. The returned app must expose its identifier as `ID` and its web URL as `HTMLURL`.
- `GetInstallation` must retrieve a specified installation.
- `ListUserInstallations` must list installations available to the authenticated user and support optional pagination.
- `CreateInstallationToken` must create an access token for a specified installation. The returned token must expose its token string as `Token`.
- `ListUserRepos` must list repositories available to the authenticated user for a specified installation and support optional pagination.
