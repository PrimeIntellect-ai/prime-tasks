Warn yarn workspaces users
Yarn workspaces are not supported yet. If any user has a `workspaces` field in their `package.json`, we should warn them about this lack of support and point them to the outstanding issue in this repo.

https://yarnpkg.com/blog/2017/08/02/introducing-workspaces/

### Additional contract requirements

- For a `package.json` with a `workspaces` field, include an additional item in the returned upgrades array.
