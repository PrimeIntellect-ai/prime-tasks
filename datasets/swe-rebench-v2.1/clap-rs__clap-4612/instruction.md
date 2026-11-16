clap_generate: zsh broken with two multi length arguments
### Please complete the following tasks

- [X] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [X] I have searched the existing issues

### Rust Version

rustc 1.58.0-nightly (8b09ba6a5 2021-11-09)

### Clap Version

3.0.0-beta.5

### Minimal reproducible code

```rust
use clap::{App, IntoApp, Parser};
use clap_generate::{generate, Shell};
use std::io::stdout;

#[derive(Parser)]
pub struct Args {
    pub targets: Vec<String>,
    #[clap(required = true, raw = true)]
    pub files: Vec<String>,
}

fn main() {
    let mut app: App = Args::into_app();
    generate(Shell::Zsh, &mut app, "bug", &mut stdout());
}
```

### Steps to reproduce the bug with the above code

With the completion installed:

```
% command <tab>
_arguments:comparguments:325: doubled rest argument definition: *::file -- Files to search for:
```


### Actual Behaviour

So I have a program that has a usage like this: `program: <targets>... -- <files>...`

The zsh completion seems to really not like this and spits out an error when tab is hit:

`_arguments:comparguments:325: doubled rest argument definition: *::file -- Files to search for:`

The completion generated is:

```sh
#compdef bug

autoload -U is-at-least

_bug() {
    typeset -A opt_args
    typeset -a _arguments_options
    local ret=1

    if is-at-least 5.2; then
        _arguments_options=(-s -S -C)
    else
        _arguments_options=(-s -C)
    fi

    local context curcontext="$curcontext" state line
    _arguments "${_arguments_options[@]}" \
'-h[Print help information]' \
'--help[Print help information]' \
'*::targets:' \
'*::files:' \
&& ret=0
}

(( $+functions[_bug_commands] )) ||
_bug_commands() {
    local commands; commands=()
    _describe -t commands 'bug commands' commands "$@"
}

_bug "$@"%
```

### Expected Behaviour

Don't be broken

### Additional Context

_No response_

### Debug Output

_No response_

### Additional contract requirements

The generated zsh completion script must not define more than one catch-all
(rest) positional argument. zsh rejects a completion script that contains a
doubled rest argument definition with an error such as
`_arguments:comparguments:325: doubled rest argument definition`, so for a
command with two multi-valued positional arguments the generated script must
emit at most one `*:` catch-all entry.
