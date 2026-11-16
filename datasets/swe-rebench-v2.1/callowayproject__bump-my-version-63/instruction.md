Constant strings interpreted as regex
* bump-my-version version: 0.9.3
* Python version: 3.11.15
* Operating System: macOS

### Description

In some circumstances, while I deactivated regex mode everywhere (both in config file and on CLI invokation), the search string gets interpreted as a regex and has unwanted side-effects.

### What I Did

Starting from a `changelog.md` file containing:

```md
# Changelog

## [0.0.1 (unreleased)](https://cool.url)

- Test unreleased package.
```

With a `pyproject.toml` file alongside containing:
```toml
[tool.bumpversion]
current_version = "0.0.1"
allow_dirty = true

[[tool.bumpversion.files]]
filename = "./changelog.md"
no_regex = true
search = "(unreleased)"
replace = "({now:%Y-%m-%d})"
```

Now let's invoke this CLI:
```shell-session
$ bump-my-version replace --verbose --dry-run --no-regex --no-configured-files --search "(unreleased)" --replace "({now:%Y-%m-%d})" ./changelog.md
Starting BumpVersion 0.9.3
Reading config file pyproject.toml:
Parsing version '0.0.1' using regexp '(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)'
Parsed the following values: major=0, minor=0, patch=1
Asserting files ./changelog.md contain the version string...
Found 're.compile('(unreleased)', re.MULTILINE|re.DOTALL)' in ./changelog.md at line 3: unreleased
Would change file ./changelog.md:
*** before ./changelog.md
--- after ./changelog.md
***************
*** 1,5 ****
  # Changelog

! ## [0.0.1 (unreleased)](https://cool.url)

! - Test unreleased package.
--- 1,5 ----
  # Changelog

! ## [0.0.1 ((2023-08-29))](https://cool.url)

! - Test (2023-08-29) package.
```

You can see here how the `(unreleased)` search string is interpreted as a regex and has unwanted side effect in `changelog.md` file.

I expect here to have the final result of that file to be:
```shell-session
# Changelog

## [0.0.1 (2023-08-29)](https://cool.url)

- Test unreleased package.
```
Instead of:
```shell-session
# Changelog

## [0.0.1 ((2023-08-29))](https://cool.url)

- Test (2023-08-29) package.
```

I have a hard time understanding what's happening.

Maybe there is a difference between in the way strings passed in the CLI are not parsed like those in the config file.

Maybe duplicating the replace action in both the config file and the CLI is messing with some internals.

Or maybe the `--no-configured-files` is not well-named, as I expect it to ignore the directives from any configuration file found. In which case what I am looking for is probably a `--no-config` option.
