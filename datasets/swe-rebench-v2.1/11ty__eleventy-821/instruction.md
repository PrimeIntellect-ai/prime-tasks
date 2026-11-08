Global data doesn’t have explicit rules about data overrides when data file roots are the same
In template and directory data files override is explicit:

`component.11tydata.js` overrides `component.11tydata.json` overrides `component.json`

No such explicit convention exists for global data files. It does one generic glob selector for these files.

https://github.com/11ty/eleventy/blob/ccbaf5af8cafeccbf5b0ecde9e8b75c2219f07c3/src/TemplateData.js#L136

Surfaced by @gloryofrobots in #635.

### Additional contract requirements

- When global data files have the same root, merge their data; for conflicting keys, `.js` overrides `.json`, `.json` overrides `.yaml`, and `.yaml` overrides `.nosj`.
