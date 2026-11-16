`no-shadow-route-definition` false positive
Hey @raido, your change hasn't been released yet, but I noticed it is causing a bunch of routes in my application to get incorrectly flagged.

Here's a test case with the issue. Would you be able to fix this? Otherwise I'll need to revert this fix before the next release.

```js
this.route('show', { path: '/:marketingEmailId' });
this.route('edit', { path: '/:marketingEmailId/edit' });
```

_Originally posted by @bmish in https://github.com/ember-cli/eslint-plugin-ember/pull/1132#issuecomment-816254737_

### Additional contract requirements

The rule reports a message of the form:

    Route "<name>" ("<fullPath>", <line>L:<column>C) is shadowing route "<name>" ("<fullPath>", <line>L:<column>C)

where each `<name>` is the route name, each `<fullPath>` is the route's normalized path string (quoted), and `<line>L:<column>C` is the source location of the route definition.

The rule module exports a function `buildErrorMessage({ leftRoute, rightRoute })` that returns this message. Each route argument has `name` (string), `fullPath` (string), and `source.loc.start.line` / `source.loc.start.column` (numbers).

Do not add a leading `/` to a reported `fullPath`: display `blog` as `"blog"`, not `"/blog"`.
