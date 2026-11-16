Files uploaded using assets with default target project_upload are not downloadable using link created in release
The link generated when publishing a release is in the format

`https://gitlab.com/-/<project path>/uploads/<upload id>/<file>` however files are available at `https://gitlab.com/-/project/<project id>/uploads/<upload id>/<file>`

This causes links in releases to return 404

### Additional contract requirements

Release links for uploaded assets must use GitLab’s downloadable project-ID upload path, including the `/uploads/<upload id>/<file>` component, rather than the project-path upload URL that returns 404.
