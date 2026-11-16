Add support for disable `emitWarning`
Currently the loader warns on 3rd party packages which have some invalid source maps. As this is typically not in the hand of the user to fix those (other than send bug reports/PRs) we should offer an option to disable warnings.

A pretty common error seems to be that source maps are included in the package, but the source maps do not contain the original source content. The references to any files break because the source files are not bundled in the npm packages.

Affected packages in my case are:

- All packages from formatjs (intl-messageformat, ...)
- All packages from Apollo (apollo-client, ...)

### Additional contract requirements

- When warnings are emitted, use these exact message formats: `Failed to parse source map from '<source URL>': <parse error>`, `Failed to parse source map from "data" URL: <source URL>`, `Failed to parse source map from '<source URL>' file: <file error>`, and `Failed to parse source map: "<URL>" URL is not supported`.
