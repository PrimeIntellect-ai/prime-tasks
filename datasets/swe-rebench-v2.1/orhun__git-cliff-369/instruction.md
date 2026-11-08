Enable having a footer like the KeepAChangelog one
**Is your feature request related to a problem? Please describe.**
In my changelogs, I would like to have a footer like the one of [KeepAChangelog](https://keepachangelog.com/en/1.1.0/):
```
[Unreleased]: https://github.com/olivierlacan/keep-a-changelog/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/olivierlacan/keep-a-changelog/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/olivierlacan/keep-a-changelog/compare/v0.2.0...v0.3.0
```

This enables you to click on the links of each entry of the changelog to see the changes.

I think this isn't possible to achieve at the moment with `git-cliff`.

Have you ever thought about supporting such a use case?

**Describe the solution you'd like**

There should be a way for git-cliff to update the footer of the changelog together with the body.

**Describe alternatives you've considered**
git-cliff could have a new entry in the configuration: `version_link`, in which the user can specify a template to add after the `[<version>]:` row.

For example, in the configuration you can have something like:
```toml
version_link = """
{% if previous %}\
{% if previous.version %}\
    https://github.com/olivierlacan/keep-a-changelog/compare/{{ previous.version }}...{{ version }}
{% else %}\
    https://github.com/olivierlacan/keep-a-changelog/releases/tag/{{ version }}
{% endif %}\
{% endif %}\
"""
```

Then, git-cliff takes care of updating the versions at the end of the changelog.

Maybe you could also have a `unreleased_link`, because the template in this case is different:
```toml
unreleased_link = """
    https://github.com/olivierlacan/keep-a-changelog/compare/{{ version }}...HEAD
"""
```

**Additional context**
Enabling "templated footers" isn't enough because every time you add a new entry to the changelog, you need to edit the `[Unreleased]` row with the latest version.

For example, the footer for the 0.3.0 version looks like this:
```
[Unreleased]: https://github.com/olivierlacan/keep-a-changelog/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/olivierlacan/keep-a-changelog/compare/v0.2.0...v0.3.0
```

Instead the footer of the 1.0.0 version looks like this:
```
[Unreleased]: https://github.com/olivierlacan/keep-a-changelog/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/olivierlacan/keep-a-changelog/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/olivierlacan/keep-a-changelog/compare/v0.2.0...v0.3.0
```

As you can see we have both added the `[1.0.0]` row, and edited the `[Unreleased]` one.

### Additional contract requirements

- The changelog footer is rendered as a template, and the rendered result is written after the changelog body.
- The footer template is rendered with the full list of releases available under the name `releases`. Each element of that list exposes the same release fields that a release exposes in the body template (for example `version`), so the footer can generate one link per release automatically.
