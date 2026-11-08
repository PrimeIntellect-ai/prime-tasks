ignore_missing_version not honored when set in config file
* bump-my-version version: 0.17.4
* Python version: 3.10.13
* Operating System: Ubuntu 22.04.4 LTS

### Description

I am trying to setup version bumping for one of our projects. The project contains a submodule that we don't want to bump and the submodule's pyproject.toml doesn't list a version.

The ignore-missing-version flag is not getting honored from the config file but does work via command line.

I am also unable to use the excluded_paths argument at all. There isn't really any documentation for using that, how is it meant to be used? I can't get it to work from the command line or from the config file.

### What I Did

I have tried applying excluded_paths both in the main config section and in the specific files group in the config file as well as via a CLI argument. The setting is never honored and bumping aborts when reaching the submodule directory.

As an alternative to outright ignoring the submodule's presence, I then tried utilizing the lack of version in the submodule's pyproject.toml file to skip over it that way. The flag is honored when used as a CLI argument but not when set in the config file.

This is the relevant section of my config file
```
[tool.bumpversion]
current_version = "2.8.2.3rc1"
parse = """(?x)
    (?P<major>0|[1-9]\\d*)\\.
    (?P<minor>0|[1-9]\\d*)\\.
    (?P<patch>0|[1-9]\\d*)
    (?:
        \\.(?P<smallpatch>0|[1-9]\\d*)
    )?                                  # smallpatch section is optional
    (?:
        (?P<pre_l>[a-zA-Z-]+)           # pre-release label
        (?P<pre_n>[1-9]\\d*)            # pre-release version number
    )?                                  # pre-release section is optional
"""
serialize = [
    "{major}.{minor}.{patch}{pre_l}{pre_n}",
    "{major}.{minor}.{patch}.{smallpatch}{pre_l}{pre_n}",
    "{major}.{minor}.{patch}.{smallpatch}",
    "{major}.{minor}.{patch}",
]
allow_dirty = true
ignore_missing_version = true

[tool.bumpversion.parts.pre_l]
values = ["dev", "rc", "final"]
optional_value = "final"

[[tool.bumpversion.files]]
glob = "<location>/*/pyproject.toml"
search = "version = \"{current_version}\""
replace = "version = \"{new_version}\""
```
when I run this I still get the 'Did not find' error ```
❯ bump-my-version bump smallpatch --current-version=2.8.2.3rc1 --config-file=./.bumpversion.toml --dry-run```

>
>  Usage: bump-my-version bump [OPTIONS] [ARGS]...
>
>  Try 'bump-my-version bump -h' for help
> ╭─ Error ──────────────────────────────────────╮
> │ Did not find 'version = "2.8.2.3rc1"' in file: 'location/submodule/pyproject.toml'                                                                                                                              │
> ╰──────────────────────────────────────────╯

but when I run that same command with the CLI flag, it works
`❯ bump-my-version bump smallpatch --current-version=2.8.2.3rc1 --config-file=./.bumpversion.toml --dry-run --ignore-missing-version`


The config file hasn't changed between those two tries.
Oddly, if I run `bump-my-version show` I see the field set correctly `'ignore_missing_version': True,` but running without the command line flag always fails.

### Additional contract requirements

When `ignore_missing_version` is enabled globally in the configuration, bumping must continue if a configured target file—including a file matched by a configured glob—does not contain the current version. Such a file is left unchanged.
