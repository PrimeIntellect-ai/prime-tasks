Switch to travis-ci.com as default
With the [support for open source projects on travis-ci.com](https://blog.travis-ci.com/2018-05-02-open-source-projects-on-travis-ci-com-with-github-apps), it is actually recommended to actually use travis-ci.com, especially for new repositories (https://docs.travis-ci.com/user/migrate/open-source-on-travis-ci-com/)

The suggestion here is to align the argument `ext` to `use_travis()` and friends to use `"com"` as default. Happy to contribute a PR.

### Additional contract requirements

- `use_travis()`, `use_travis_badge()` and `browse_travis()` are public functions of the usethis package. Each accepts an `ext` argument that selects the Travis CI host; its default is `"com"` (i.e. `https://travis-ci.com`), while `ext = "org"` selects `https://travis-ci.org`.
- `use_travis()` also accepts a `browse` argument controlling whether a browser window is opened.
- `browse_travis(package = NULL, ext = c("com", "org"))` returns the full Travis CI URL as a character string, for example `"https://travis-ci.com/r-lib/usethis"`.
