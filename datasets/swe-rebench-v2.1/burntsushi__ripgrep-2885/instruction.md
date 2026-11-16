Alternation match regression
### Please tick this box to confirm you have reviewed the above.

- [X] I have a different issue.

### What version of ripgrep are you using?

14.1.0

### How did you install ripgrep?

Cargo

### What operating system are you using ripgrep on?

Fedora 40

### Describe your bug.

ripgrep fails to return some matches when case is ignored. This only happens with very particular matches and specific characters.

A git bisect seems to suggest this is a regression introduced by
ca740d9ace9065103036c101ca973b79e59ae85a.

### What are the steps to reproduce the behavior?

Run the following:
```
echo -n "e-x" | rg -i "e.x|ex"
```


### What is the actual behavior?

```
$ echo -n "e-x" | rg --debug -i "e.x|ex"
rg: DEBUG|rg::flags::config|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/ripgrep-14.1.0/crates/core/flags/config.rs:41: /home/ido/.ripgreprc: arguments loaded from config file: []
rg: DEBUG|rg::flags::parse|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/ripgrep-14.1.0/crates/core/flags/parse.rs:97: no extra arguments found from configuration file
rg: DEBUG|rg::flags::hiargs|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/ripgrep-14.1.0/crates/core/flags/hiargs.rs:1099: using heuristics to determine whether to read from stdin or search ./ (is_readable_stdin=true, stdin_consumed=false, mode=Search(Standard))
rg: DEBUG|rg::flags::hiargs|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/ripgrep-14.1.0/crates/core/flags/hiargs.rs:1112: heuristic chose to search stdin
rg: DEBUG|rg::flags::hiargs|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/ripgrep-14.1.0/crates/core/flags/hiargs.rs:1260: found hostname for hyperlink configuration: sourcerer
rg: DEBUG|rg::flags::hiargs|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/ripgrep-14.1.0/crates/core/flags/hiargs.rs:1270: hyperlink format: ""
rg: DEBUG|rg::flags::hiargs|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/ripgrep-14.1.0/crates/core/flags/hiargs.rs:174: using 1 thread(s)
rg: DEBUG|grep_regex::literal|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/grep-regex-0.1.12/src/literal.rs:117: extracted fast line regex: "(?:(?:EX)|(?:Ex)|(?:eX)|(?:ex))"
rg: DEBUG|globset|/home/ido/.cargo/registry/src/index.crates.io-6f17d22bba15001f/globset-0.4.14/src/lib.rs:453: built glob set; 0 literals, 0 basenames, 12 extensions, 0 prefixes, 0 suffixes, 0 required extensions, 0 regexes
$
```

### What is the expected behavior?

ripgrep should have returned `e-x` instead of returning no matches.
The same occurs when `e` is replaced with `k`, `s`, or `t`, but doesn't with any other alphabetic character, or if case isn't ignored.
