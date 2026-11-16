--help message randomly show and hide docs lines
### Please complete the following tasks

- [X] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [X] I have searched the existing issues

### Rust Version

rustc 1.58.0-nightly (e249ce6b2 2021-10-30)

### Clap Version

3.0.0-beta.5

### Minimal reproducible code

```rust
use clap::Parser;

#[derive(Parser, Debug)]
#[clap(version, about)]
pub struct Opts {
    #[clap(subcommand)]
    pub cmd: Subcommand,
}

// Ouch commands:
// - `compress`
// - `decompress`
// - `list`
//
// Clap commands:
//  - `help`
/// Repository: https://github.com/ouch-org/ouch
#[derive(Parser, PartialEq, Eq, Debug)]
pub enum Subcommand {
    Compress { output: String },
}

fn main() {
    let _ = Opts::parse();
}
```

### Steps to reproduce the bug with the above code

`cargo run -q -- --help`

### Actual Behaviour

This is a tricky one, if you copy my code example, here is the --help message:

```
teste 0.1.0



USAGE:
    teste <SUBCOMMAND>

OPTIONS:
    -h, --help       Print help information
    -V, --version    Print version information

SUBCOMMANDS:
    compress
    help        Print this message or the help of the given subcommand(s)
```

So, that `Repository` line does not appear in the help message :-1:, but if we change all the `//` comments to be `///` (to three slashes):

```
teste 0.1.0

Ouch commands: - `compress` - `decompress` - `list`

Clap commands: - `help` Repository: https://github.com/ouch-org/ouch

USAGE:
    teste <SUBCOMMAND>

OPTIONS:
    -h, --help
            Print help information

    -V, --version
            Print version information

SUBCOMMANDS:
    compress

    help
            Print this message or the help of the given subcommand(s)
```

Now it appears!! :+1:.

Now try deleting the empty comment `"///\n"`. Does not appear anymore :-1:.
Now you delete the `#[clap(version, about)]` line. Appears again :+1:.

So, we went :-1: -> :+1: -> :-1: -> :+1: just by making small random changes.

### Expected Behaviour

I assume it should be consistent and always show that repository line.

### Additional Context

_No response_

### Debug Output

With the starter code:

```
[            clap::build::app] 	App::_do_parse
[            clap::build::app] 	App::_build
[            clap::build::app] 	App::_propagate:teste
[            clap::build::app] 	App::_check_help_and_version
[            clap::build::app] 	App::_check_help_and_version: Building help subcommand
[            clap::build::app] 	App::_propagate_global_args:teste
[            clap::build::app] 	App::_derive_display_order:teste
[            clap::build::app] 	App::_derive_display_order:compress
[            clap::build::app] 	App::_derive_display_order:help
[clap::build::app::debug_asserts] 	App::_debug_asserts
[clap::build::arg::debug_asserts] 	Arg::_debug_asserts:help
[clap::build::arg::debug_asserts] 	Arg::_debug_asserts:version
[         clap::parse::parser] 	Parser::get_matches_with
[         clap::parse::parser] 	Parser::_build
[         clap::parse::parser] 	Parser::_verify_positionals
[         clap::parse::parser] 	Parser::get_matches_with: Begin parsing 'RawOsStr("--help")' ([45, 45, 104, 101, 108, 112])
[         clap::parse::parser] 	Parser::get_matches_with: Positional counter...1
[         clap::parse::parser] 	Parser::get_matches_with: Low index multiples...false
[         clap::parse::parser] 	Parser::possible_subcommand: arg=RawOsStr("--help")
[         clap::parse::parser] 	Parser::get_matches_with: sc=None
[         clap::parse::parser] 	Parser::parse_long_arg
[         clap::parse::parser] 	Parser::parse_long_arg: cur_idx:=1
[         clap::parse::parser] 	Parser::parse_long_arg: Does it contain '='...
[         clap::parse::parser] 	No
[         clap::parse::parser] 	Parser::parse_long_arg: Found valid opt or flag '--help'
[         clap::parse::parser] 	Parser::check_for_help_and_version_str
[         clap::parse::parser] 	Parser::check_for_help_and_version_str: Checking if --RawOsStr("help") is help or version...
[         clap::parse::parser] 	Help
[         clap::parse::parser] 	Parser::get_matches_with: After parse_long_arg HelpFlag
[         clap::parse::parser] 	[         clap::parse::parser] 	Parser::use_long_help
Parser::help_err: use_long=false
[         clap::parse::parser] 	Parser::use_long_help
[          clap::output::help] 	Help::new
[          clap::output::help] 	Help::write_help
[          clap::output::help] 	should_show_arg: use_long=false, arg=help
[          clap::output::help] 	Help::write_templated_help
[          clap::output::help] 	Help::write_before_help
[          clap::output::help] 	Help::write_bin_name
[         clap::output::usage] 	Usage::create_usage_no_title
[         clap::output::usage] 	Usage::create_help_usage; incl_reqs=true
[         clap::output::usage] 	Usage::get_required_usage_from: incls=[], matcher=false, incl_last=false
[         clap::output::usage] 	Usage::get_required_usage_from: unrolled_reqs={}
[         clap::output::usage] 	Usage::get_required_usage_from: ret_val=[]
[         clap::output::usage] 	Usage::needs_options_tag
[         clap::output::usage] 	Usage::needs_options_tag:iter: f=help
[         clap::output::usage] 	Usage::needs_options_tag:iter Option is built-in
[         clap::output::usage] 	Usage::needs_options_tag:iter: f=version
[         clap::output::usage] 	Usage::needs_options_tag:iter Option is built-in
[         clap::output::usage] 	Usage::needs_options_tag: [OPTIONS] not required
[         clap::output::usage] 	Usage::create_help_usage: usage=teste <SUBCOMMAND>
[          clap::output::help] 	Help::write_all_args
[          clap::output::help] 	should_show_arg: use_long=false, arg=help
[          clap::output::help] 	should_show_arg: use_long=false, arg=version
[          clap::output::help] 	Help::write_args
[          clap::output::help] 	should_show_arg: use_long=false, arg=help
[          clap::output::help] 	Help::write_args: Current Longest...2
[          clap::output::help] 	Help::write_args: New Longest...6
[          clap::output::help] 	should_show_arg: use_long=false, arg=version
[          clap::output::help] 	Help::write_args: Current Longest...6
[          clap::output::help] 	Help::write_args: New Longest...9
[          clap::output::help] 	should_show_arg: use_long=false, arg=help
[          clap::output::help] 	Help::spec_vals: a=--help
[          clap::output::help] 	should_show_arg: use_long=false, arg=version
[          clap::output::help] 	Help::spec_vals: a=--version
[          clap::output::help] 	Help::spec_vals: a=--help
[          clap::output::help] 	Help::short
[          clap::output::help] 	Help::long
[          clap::output::help] 	Help::val: arg=help
[          clap::output::help] 	Help::val: Has switch...
[          clap::output::help] 	Yes
[          clap::output::help] 	Help::val: nlh...false
[          clap::output::help] 	Help::help
[          clap::output::help] 	Help::help: Next Line...false
[          clap::output::help] 	Help::help: Too long...
[          clap::output::help] 	No
[          clap::output::help] 	Help::spec_vals: a=--version
[          clap::output::help] 	Help::short
[          clap::output::help] 	Help::long
[          clap::output::help] 	Help::val: arg=version
[          clap::output::help] 	Help::val: Has switch...
[          clap::output::help] 	Yes
[          clap::output::help] 	Help::val: nlh...false
[          clap::output::help] 	Help::help
[          clap::output::help] 	Help::help: Next Line...false
[          clap::output::help] 	Help::help: Too long...
[          clap::output::help] 	No
[          clap::output::help] 	Help::write_subcommands
[          clap::output::help] 	Help::write_subcommands longest = 8
[          clap::output::help] 	Help::sc_spec_vals: a=compress
[          clap::output::help] 	Help::sc_spec_vals: a=help
[          clap::output::help] 	Help::write_subcommand
[          clap::output::help] 	Help::sc_spec_vals: a=compress
[          clap::output::help] 	Help::help
[          clap::output::help] 	Help::help: Next Line...false
[          clap::output::help] 	Help::help: Too long...
[          clap::output::help] 	No
[          clap::output::help] 	Help::write_subcommand
[          clap::output::help] 	Help::sc_spec_vals: a=help
[          clap::output::help] 	Help::help
[          clap::output::help] 	Help::help: Next Line...false
[          clap::output::help] 	Help::help: Too long...
[          clap::output::help] 	No
[          clap::output::help] 	Help::write_after_help
[           clap::output::fmt] 	is_a_tty: stderr=false
```

### Additional contract requirements

- For a derived parser whose struct doc comment is `Opts doc comment summary`, `Opts::into_app()` must return `None` from `get_long_about()`.
