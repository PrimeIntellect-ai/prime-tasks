addon templates were detected, but no template compilers were registered.
As an addon author, I would like a template compiler to be automatically registered for me when I need it, so I avoid the error message below. Is there a reasonable way to for ember-cli to do this?

Error message:
"Addon templates were detected but there are no template compilers registered for (addon-name). Please make sure your template precompiler (commonly ember-cli-htmlbars) is listed in dependences (NOT devDependencies) in (addon-name)'s package.json."

### Additional contract requirements

- When a new addon is generated, its generated `package.json` must list `ember-cli-htmlbars` under `dependencies`.
- In that same generated `package.json`, `ember-cli-htmlbars` must no longer appear under `devDependencies`; it is moved, not duplicated.
