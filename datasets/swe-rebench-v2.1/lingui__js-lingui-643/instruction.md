Cannot read property 'locale' of null for `@lingui/loader`
**Describe the bug**
App crashes when using `@lingui/loader`

**To Reproduce**
Install deps and run example of `create-react-app` from `next` branch.

**Expected behavior**
It should work :)

**Additional context**
![image](https://user-images.githubusercontent.com/1096340/79052362-4e2ef580-7c36-11ea-9e14-d9bd15691e4d.png)

It's coming from this line. Apparently the `getCatalogForFile` returns `null` for some reason. I will investigate it further, but I suspect it's a classic issue of wrong path separators (I am on Windows).

https://github.com/lingui/js-lingui/blob/24d521ff385647f69f73188fd35e07079efdc1f3/packages/loader/src/index.js#L41

- jsLingui version ``lingui --version``: 3.0.0-10

### Additional contract requirements

- When a file matches a catalog path, catalog lookup must resolve the matching catalog and locale even when the relevant paths use Windows-style backslash separators.
