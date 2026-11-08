Empty string replacement (`--replace ""`) is interpreted as absence of parameter
* bump-my-version version: 0.15.4
* Python version: 3.12.1
* Operating System: macOS 14.2.1

### Description

A simple search and replace of plain string by an empty one is polluted by non-matching rules from the configuration file.

This is a follow-up of #70.

### What I Did

Here are my files:

* `pyproject.toml`:
  ```toml
  [tool.bumpversion]
  current_version = "2.21.1"
  allow_dirty = true

  [[tool.bumpversion.files]]
  filename = "./changelog.md"
  search = "random"
  replace = "blah_blah_blah"
  ```

* `changelog.md`:
  ```md
   Changelog

  ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

  - Test profanity.
  ```

Here I'm trying to replace the `profanity` string by `XXX` with this CLI invokation, and it works:

```shell-session
$ bump-my-version replace --dry-run --verbose --no-configured-files --allow-dirty --ignore-missing-version --search "profanity" --replace "XXX" ./changelog.md
Starting BumpVersion 0.15.4
Reading configuration
  Reading config file: /Users/kde/bump_test/pyproject.toml
Parsing version '2.21.1' using regexp '(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)'
  Parsed the following values: major=2, minor=21, patch=1

File ./changelog.md: replace `profanity` with `XXX`
  Found 'profanity' at line 5: profanity
  Would change file ./changelog.md:
    *** before ./changelog.md
    --- after ./changelog.md
    ***************
    *** 2,5 ****

      ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

    ! - Test profanity.
    --- 2,5 ----

      ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

    ! - Test XXX.

File ./changelog.md: replace `profanity` with `XXX`
  Found 'profanity' at line 5: profanity
  Would change file ./changelog.md:
    *** before ./changelog.md
    --- after ./changelog.md
    ***************
    *** 2,5 ****

      ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

    ! - Test profanity.
    --- 2,5 ----

      ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

    ! - Test XXX.
```

It works as expected, with the only small annoyance that the replacement action seems to be called twice. Maybe this is just a detail of the way the replacement action is reported, or it might indicate a trickier problem. Anyway.

Now instead of `XXX`, I want to remove the `profanity` entirely, and replace it by an empty string.

So here I call the same CLI as above, but use the `--replace ""` option instead:

```shell-session
$ bump-my-version replace --dry-run --verbose --no-configured-files --allow-dirty --ignore-missing-version --search "profanity" --replace "" ./changelog.md
Starting BumpVersion 0.15.4
Reading configuration
  Reading config file: /Users/kde/bump_test/pyproject.toml
Parsing version '2.21.1' using regexp '(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)'
  Parsed the following values: major=2, minor=21, patch=1

File ./changelog.md: replace `profanity` with `{new_version}`
  Found 'profanity' at line 5: profanity
  Would change file ./changelog.md:
    *** before ./changelog.md
    --- after ./changelog.md
    ***************
    *** 2,5 ****

      ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

    ! - Test profanity.
    --- 2,5 ----

      ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

    ! - Test 2.21.1.

File ./changelog.md: replace `profanity` with `blah_blah_blah`
  Found 'profanity' at line 5: profanity
  Would change file ./changelog.md:
    *** before ./changelog.md
    --- after ./changelog.md
    ***************
    *** 2,5 ****

      ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

    ! - Test profanity.
    --- 2,5 ----

      ## [2.21.1 (unreleased)](https://github.com/kdeldycke/workflows/compare/v2.21.0...main)

    ! - Test blah_blah_blah.
```

I expect there the changed line in  `./changelog.md`  to be `- Test .`, but instead, I get two conflicting results:
- the first in which `profanity` is replaced by the current version (`2.21.1`)
- the second in which `profanity` is replaced by the unrelated `blah_blah_blah` string that has been hard-coded in the `pyproject.toml` file

By the nature of this edge-case, it feels like somewhere in the code path, the empty string passed to `--replace` is normalized to `None`, as if `--replace` hasn't been used at all.
