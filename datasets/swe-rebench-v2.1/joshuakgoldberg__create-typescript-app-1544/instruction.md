🚀 Feature: Add prettier-plugin-sh
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

As of https://github.com/un-ts/prettier/issues/340 -> https://github.com/un-ts/prettier/pull/341, `prettier-plugin-sh` can work on `.nvmrc`. That means it can replace the last `overrides` in `.prettierrc.json`!

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/07c0abcee146346ba819ab444ddad298fb698c2a/.prettierrc.json#L3

Let's add that in. It's also a generally useful plugin for expanding the range of file extensions / syntax Prettier will format.

### Additional Info

_No response_

### Additional contract requirements

- The repository's own Prettier configuration must register `prettier-plugin-sh`, and the repository must declare the plugin as a dependency so it is available to Prettier.
- Projects created by the tool must register `prettier-plugin-sh` in their Prettier configuration and include it among the dependencies installed for the generated project.
