Opposing/negating command-line options (eg. --no-hidden)
Background
-------------
First off, let me just say that I love your projects, `bat` and `fd` are great and I use them both regularly.

What I was looking for was something similar to the `--no-hidden` option as it exists in ripgrep. As in fd, in ripgrep hidden files are not searched by default. However with ripgrep I can create a global config that effectively changes it's behavior to search hidden files by default, and then still be able to pass a `--no-hidden` option in order to turn it back off on a case by case basis when desired. The logic that parses the command-line options would simply let subsequent opposing command-line options override prior ones. When I was looking around to see if this was possible, I found https://github.com/sharkdp/fd/issues/362 where a global config file that was previously proposed, and I agree that aliases adequately satisfy the same use case.

Proposal
----------
If so-called "opposing" command-line options such as `--no-hidden` were supported. Then it would be possible to define aliases such as

```bash
alias fd='fd --hidden'
```
which would effectively change the default options to search hidden files, and then if you wanted to ignore hidden files you could run something like:

```bash
fd --no-hidden
```

Similarly other "opposing" command-line options could be added where applicable, for example the currently supported `--no-ignore` could be complemented with a new `--ignore` option.

Just briefly looking at the currently supported options, here are some of the ones I feel could possibly be useful:

Currently Supported Option  | Potential "Opposing" Option
:---:                                          | :---:
--hidden                                  | --no-hidden
--no-ignore                             | --ignore
--no-ignore-vcs                     | --ignore-vcs
--follow                                    | --no-follow
--fixed-strings                        | --no-fixed-strings
--show-errors                         | --no-show-errors
--absolute-path                     | --relative-path
--full-path                               | --no-full-path


Note that I haven't tested it, but for some currently supported options, this may or may not already be possible:

Currently Supported Option  | "Opposing" Supported Option
:---:                                          | :---:
--case-sensitive                     | --ignore-case
--glob foo*                              | --exclude foo*

How do you feel about this? If you would be interested in supporting anything like this in fd that would be awesome. If it helped, I could offer to write an initial implementation. I do have a full-time day job so depending on how involved it ended up being I couldn't guarantee how quickly I could finish it, but I would definitely find some time to do it sooner or later. I would expect that the necessary changes would be mostly, if not fully contained within the command-line parsing logic, but I haven't actually looked into it so you never know.

### Additional contract requirements

The following opposing command-line options must be supported. Each one overrides its counterpart: when both an option and its opposing option are supplied, the opposing option takes precedence, so the search behaves as if neither had been supplied.

- `--no-hidden` overrides `--hidden`
- `--ignore` overrides `--no-ignore`
- `--ignore-vcs` overrides `--no-ignore-vcs`
- `--no-follow` overrides `--follow`
- `--relative-path` overrides `--absolute-path`

The `-u`/`--unrestricted` option is an alias for `--no-ignore`, and for `--no-ignore --hidden` when given twice. The opposing options `--ignore` and `--no-hidden` override it as well.
