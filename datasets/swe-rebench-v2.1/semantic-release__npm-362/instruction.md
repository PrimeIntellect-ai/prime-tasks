get-registry.js doesn't take into account NPM_CONFIG_USERCONFIG
When `get-registry.js` looks for the registry it just looks at `./.npmrc` instead of taking into account `NPM_CONFIG_USERCONFIG`. This ends up requiring that you specify `NPM_CONFIG_REGISTRY` when you shouldn't have to because it's already in the alternative rc file specified by `NPM_CONFIG_USERCONFIG`.
