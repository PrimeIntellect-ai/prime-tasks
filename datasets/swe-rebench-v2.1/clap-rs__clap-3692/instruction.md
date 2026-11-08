Incorrectly splitting a URL (when wrapping)
### Please complete the following tasks

- [X] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [X] I have searched the existing issues

### Rust Version

rustc 1.57.0 (f1edd0429 2021-11-29)

### Clap Version

2.33.3

### Minimal reproducible code

```rust
fn main() {
    let mut app = App::new("Example");
    app = app.subcommand(SubCommand::with_name("update").arg(
        Arg::with_name("force-non-host")
            .help("Install toolchains that require an emulator. See https://github.com/rust-lang/rustup/wiki/Non-host-toolchains")
            .long("force-non-host")
            .takes_value(false)));
    let res = app.get_matches();
    println!("{:?}", res);
}
```

### Steps to reproduce the bug with the above code

If you run this with `cargo run -- update --help` you'll see the help text.  If your terminal is narrow you'll notice that the URL gets word-broken.

Interestingly, if you shorten the text before the URL  to fewer characters than the number of columns in the terminal (I was testing with a 35 column terminal, and at 32 characters before the URL it worked but at 33 it incorrectly broke the URL word.

### Actual Behaviour

The URL is "word broken".

### Expected Behaviour

I would expect the URL to not be broken, no matter how long it is, so that terminals can detect the full URL to permit clicking on it.

Interestingly it word-breaks the URL even on very very wide terminals.


### Additional Context

This reproduces in `rustup`, particularly in

```rust
.arg(Arg::with_name("force-non-host")
     .help("Install toolchains that require an emulator. See https://github.com/rust-lang/rustup/wiki/Non-host-toolchains")
     .long("force-non-host")
     .takes_value(false)),
```

As per https://github.com/rust-lang/rustup/issues/2920


### Debug Output

```
     Running `target/debug/foo update --help`
DEBUG:clap:Parser::add_subcommand: term_w=None, name=update
DEBUG:clap:Parser::propagate_settings: self=Example, g_settings=AppFlags(
    (empty),
)
DEBUG:clap:Parser::propagate_settings: sc=update, settings=AppFlags(
    NEEDS_LONG_HELP | NEEDS_LONG_VERSION | NEEDS_SC_HELP | UTF8_NONE | COLOR_AUTO,
), g_settings=AppFlags(
    (empty),
)
DEBUG:clap:Parser::propagate_settings: self=update, g_settings=AppFlags(
    (empty),
)
DEBUG:clap:Parser::get_matches_with;
DEBUG:clap:Parser::create_help_and_version;
DEBUG:clap:Parser::create_help_and_version: Building --help
DEBUG:clap:Parser::create_help_and_version: Building --version
DEBUG:clap:Parser::create_help_and_version: Building help
DEBUG:clap:Parser::get_matches_with: Begin parsing '"update"' ([117, 112, 100, 97, 116, 101])
DEBUG:clap:Parser::is_new_arg:"update":NotFound
DEBUG:clap:Parser::is_new_arg: arg_allows_tac=false
DEBUG:clap:Parser::is_new_arg: probably value
DEBUG:clap:Parser::is_new_arg: starts_new_arg=false
DEBUG:clap:Parser::possible_subcommand: arg="update"
DEBUG:clap:Parser::get_matches_with: possible_sc=true, sc=Some("update")
DEBUG:clap:Parser::parse_subcommand;
DEBUG:clap:usage::get_required_usage_from: reqs=[], extra=None
DEBUG:clap:usage::get_required_usage_from: after init desc_reqs=[]
DEBUG:clap:usage::get_required_usage_from: no more children
DEBUG:clap:usage::get_required_usage_from: final desc_reqs=[]
DEBUG:clap:usage::get_required_usage_from: args_in_groups=[]
DEBUG:clap:Parser::parse_subcommand: About to parse sc=update
DEBUG:clap:Parser::parse_subcommand: sc settings=AppFlags(
    NEEDS_LONG_HELP | NEEDS_LONG_VERSION | NEEDS_SC_HELP | UTF8_NONE | COLOR_AUTO,
)
DEBUG:clap:Parser::get_matches_with;
DEBUG:clap:Parser::create_help_and_version;
DEBUG:clap:Parser::create_help_and_version: Building --help
DEBUG:clap:Parser::create_help_and_version: Building --version
DEBUG:clap:Parser::get_matches_with: Begin parsing '"--help"' ([45, 45, 104, 101, 108, 112])
DEBUG:clap:Parser::is_new_arg:"--help":NotFound
DEBUG:clap:Parser::is_new_arg: arg_allows_tac=false
DEBUG:clap:Parser::is_new_arg: -- found
DEBUG:clap:Parser::is_new_arg: starts_new_arg=true
DEBUG:clap:Parser::possible_subcommand: arg="--help"
DEBUG:clap:Parser::get_matches_with: possible_sc=false, sc=None
DEBUG:clap:ArgMatcher::process_arg_overrides:None;
DEBUG:clap:Parser::parse_long_arg;
DEBUG:clap:Parser::parse_long_arg: Does it contain '='...No
DEBUG:clap:Parser::parse_long_arg: Found valid flag '--help'
DEBUG:clap:Parser::check_for_help_and_version_str;
DEBUG:clap:Parser::check_for_help_and_version_str: Checking if --help is help or version...Help
DEBUG:clap:Parser::_help: use_long=true
DEBUG:clap:Help::write_parser_help;
DEBUG:clap:Help::write_parser_help;
DEBUG:clap:Parser::color;
DEBUG:clap:Parser::color: Color setting...Auto
DEBUG:clap:is_a_tty: stderr=false
DEBUG:clap:Help::new;
DEBUG:clap:Help::write_help;
DEBUG:clap:Help::write_default_help;
DEBUG:clap:Help::write_bin_name;
DEBUG:clap:Help::write_version;
DEBUG:clap:usage::create_usage_no_title;
DEBUG:clap:usage::get_required_usage_from: reqs=[], extra=None
DEBUG:clap:usage::get_required_usage_from: after init desc_reqs=[]
DEBUG:clap:usage::get_required_usage_from: no more children
DEBUG:clap:usage::get_required_usage_from: final desc_reqs=[]
DEBUG:clap:usage::get_required_usage_from: args_in_groups=[]
DEBUG:clap:usage::needs_flags_tag;
DEBUG:clap:usage::needs_flags_tag:iter: f=force-non-host;
DEBUG:clap:Parser::groups_for_arg: name=force-non-host
DEBUG:clap:Parser::groups_for_arg: No groups defined
DEBUG:clap:usage::needs_flags_tag:iter: [FLAGS] required
DEBUG:clap:usage::create_help_usage: usage=foo update [FLAGS]
DEBUG:clap:Help::write_all_args;
DEBUG:clap:Help::write_args;
DEBUG:clap:Help::write_args: Current Longest...2
DEBUG:clap:Help::write_args: New Longest...16
DEBUG:clap:Help::write_args: Current Longest...16
DEBUG:clap:Help::write_args: New Longest...16
DEBUG:clap:Help::write_args: Current Longest...16
DEBUG:clap:Help::write_args: New Longest...16
DEBUG:clap:Help::write_arg;
DEBUG:clap:Help::short;
DEBUG:clap:Help::long;
DEBUG:clap:Help::val: arg=--force-non-host
DEBUG:clap:Help::spec_vals: a=--force-non-host
DEBUG:clap:Help::val: Has switch...Yes
DEBUG:clap:Help::val: force_next_line...false
DEBUG:clap:Help::val: nlh...false
DEBUG:clap:Help::val: taken...28
DEBUG:clap:Help::val: help_width > (width - taken)...93 > (120 - 28)
DEBUG:clap:Help::val: longest...16
DEBUG:clap:Help::val: next_line...No
DEBUG:clap:write_spaces!: num=4
DEBUG:clap:Help::help;
DEBUG:clap:Help::help: Next Line...false
DEBUG:clap:Help::help: Too long...Yes
DEBUG:clap:Help::help: help...23456789012345678901234567890 23 https://github.com/rust-lang/rustup/wiki/Non-host-toolchains
DEBUG:clap:Help::help: help width...93
DEBUG:clap:Help::help: Usable space...92
DEBUG:clap:write_spaces!: num=28
DEBUG:clap:Help::write_arg;
DEBUG:clap:Help::short;
DEBUG:clap:Help::long;
DEBUG:clap:Help::val: arg=--help
DEBUG:clap:Help::spec_vals: a=--help
DEBUG:clap:Help::val: Has switch...Yes
DEBUG:clap:Help::val: force_next_line...false
DEBUG:clap:Help::val: nlh...false
DEBUG:clap:Help::val: taken...28
DEBUG:clap:Help::val: help_width > (width - taken)...23 > (120 - 28)
DEBUG:clap:Help::val: longest...16
DEBUG:clap:Help::val: next_line...No
DEBUG:clap:write_spaces!: num=14
DEBUG:clap:Help::help;
DEBUG:clap:Help::help: Next Line...false
DEBUG:clap:Help::help: Too long...No
DEBUG:clap:Help::write_arg;
DEBUG:clap:Help::short;
DEBUG:clap:Help::long;
DEBUG:clap:Help::val: arg=--version
DEBUG:clap:Help::spec_vals: a=--version
DEBUG:clap:Help::val: Has switch...Yes
DEBUG:clap:Help::val: force_next_line...false
DEBUG:clap:Help::val: nlh...false
DEBUG:clap:Help::val: taken...28
DEBUG:clap:Help::val: help_width > (width - taken)...26 > (120 - 28)
DEBUG:clap:Help::val: longest...16
DEBUG:clap:Help::val: next_line...No
DEBUG:clap:write_spaces!: num=11
DEBUG:clap:Help::help;
DEBUG:clap:Help::help: Next Line...false
DEBUG:clap:Help::help: Too long...No
foo-update

USAGE:
    foo update [FLAGS]

FLAGS:
        --force-non-host    23456789012345678901234567890 23 https://github.com/rust-lang/rustup/wiki/Non-host-
                            toolchains
    -h, --help              Prints help information
    -V, --version           Prints version information
```

### Additional contract requirements

- In the 30-column `update` help case with the `--force-non-host` description shown in the issue, the URL must remain a single unbroken sequence, even if it exceeds the remaining line width.
