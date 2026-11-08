porcelain: 'abbrev' parameter is ignored when describing tagless repositories
Hello,

This may be a known/expected behaviour, based on the [logic](https://github.com/jelmer/dulwich/blob/77c2d8d10695a6dfded196a927047eecf88c542f/dulwich/porcelain.py#L2223-L2225) and [`todo` comment](https://github.com/jelmer/dulwich/blob/77c2d8d10695a6dfded196a927047eecf88c542f/dulwich/porcelain.py#L2182-L2183), but I thought it'd be worth reporting since it has surprised me once or twice, and I don't find existing bugreports about it.

When running `porcelain.describe` on a repository that contains no annotated `git` tags, the `abbrev` argument (prefix-length to return from the `git` commit ID) appears to be ignored and the output includes a commit prefix length of `7` (the default).

For example, to replicate this:

```sh
$ git clone https://github.com/jelmer/dulwich/ && cd dulwich
$ for tag in $(git tag -l); do git tag --delete ${tag}; done;
$ PYTHONPATH=. python3
Python 3.12.8 (main, Dec 13 2024, 13:19:48) [GCC 14.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> from dulwich import porcelain
>>> porcelain.describe(".", abbrev=10)
'g77c2d8d'
```

When an annotated tag exists in the history, a correctly-abbreviated commit prefix is produced (along with the expected contextual formatting describing the tag it relates to).

```sh
$ git tag testing a029d7b2cc83c26a53d8b2a24fa12c340fcfac59 --annotate --message "Archaeology Today"
$ PYTHONPATH=. python3
Python 3.12.8 (main, Dec 13 2024, 13:19:48) [GCC 14.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> from dulwich import porcelain
>>> porcelain.describe(".", abbrev=10)
'testing-4746-g77c2d8d106'
```

[HIDDEN]

### Additional contract requirements

- When `porcelain.describe` has no annotated tag available, a supplied `abbrev` value must determine the length of the commit-ID prefix in the description, rather than defaulting to seven characters.
