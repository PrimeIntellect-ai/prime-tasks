Migrate from deprecated Tags API endpoint to Release API endpoint
In GitLab 14.0, the ability to manage release data (i.e. release notes) through the `/projects/<project id>/repository/tags/<tag name>/release` endpoint will be removed: https://gitlab.com/gitlab-org/gitlab/-/issues/290311

This module currently uses this endpoint to create a release in `publish.js`:

https://github.com/semantic-release/gitlab/blob/81cd6a88972e2e59ca6cf5d89ecea9d4529cdc9e/lib/publish.js#L71

This API call should be updated to use the [Release API](https://docs.gitlab.com/ee/api/releases/#create-a-release) instead.

### Additional contract requirements

- The `POST /projects/<project id>/releases` request body must include `assets: {links: []}` when there are no uploaded assets. For an uploaded asset, include it in `assets.links` as `{name: ..., url: ...}`, where `name` is its label when supplied or its alt text otherwise, and `url` is its GitLab project upload URL.
