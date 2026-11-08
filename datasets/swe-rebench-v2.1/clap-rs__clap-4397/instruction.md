`exclusive(true)` worked in `v4.0.6` and broke in `v4.0.7`
### Please complete the following tasks

- [X] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [X] I have searched the [open](https://github.com/clap-rs/clap/issues) and [rejected](https://github.com/clap-rs/clap/issues?q=is%3Aissue+label%3AS-wont-fix+is%3Aclosed) issues

### Rust Version

rustc 1.62.1 (gentoo)

### Clap Version

4.0.15

### Minimal reproducible code

```rust
use clap::Parser;

#[derive(Debug, Parser)]
struct Opts {
    /// Foo!
    #[clap(exclusive(true), long)]
    foo: bool,
}

fn main() {
    Opts::parse();
}
```

### Steps to reproduce the bug with the above code

```bash
cargo run -- --foo
```

### Actual Behaviour

> error: The argument '--foo' cannot be used with one or more of the other specified arguments

### Expected Behaviour

No errors

### Additional Context

_No response_

### Debug Output

```
    Finished dev [unoptimized + debuginfo] target(s) in 0.02s
     Running `target/debug/clap-mre --foo`
[      clap::builder::command] 	Command::_do_parse
[      clap::builder::command] 	Command::_build: name="clap-mre"
[      clap::builder::command] 	Command::_propagate:clap-mre
[      clap::builder::command] 	Command::_check_help_and_version:clap-mre expand_help_tree=false
[      clap::builder::command] 	Command::long_help_exists
[      clap::builder::command] 	Command::_check_help_and_version: Building default --help
[      clap::builder::command] 	Command::_propagate_global_args:clap-mre
[clap::builder::debug_asserts] 	Command::_debug_asserts
[clap::builder::debug_asserts] 	Arg::_debug_asserts:foo
[clap::builder::debug_asserts] 	Arg::_debug_asserts:help
[clap::builder::debug_asserts] 	Command::_verify_positionals
[        clap::parser::parser] 	Parser::get_matches_with
[        clap::parser::parser] 	Parser::get_matches_with: Begin parsing 'RawOsStr("--foo")' ([45, 45, 102, 111, 111])
[        clap::parser::parser] 	Parser::possible_subcommand: arg=Ok("--foo")
[        clap::parser::parser] 	Parser::get_matches_with: sc=None
[        clap::parser::parser] 	Parser::parse_long_arg
[        clap::parser::parser] 	Parser::parse_long_arg: Does it contain '='...
[        clap::parser::parser] 	Parser::parse_long_arg: Found valid arg or flag '--foo'
[        clap::parser::parser] 	Parser::parse_long_arg("foo"): Presence validated
[        clap::parser::parser] 	Parser::react action=SetTrue, identifier=Some(Long), source=CommandLine
[        clap::parser::parser] 	Parser::react: has default_missing_vals
[        clap::parser::parser] 	Parser::remove_overrides: id="foo"
[   clap::parser::arg_matcher] 	ArgMatcher::start_custom_arg: id="foo", source=CommandLine
[      clap::builder::command] 	Command::groups_for_arg: id="foo"
[   clap::parser::arg_matcher] 	ArgMatcher::start_custom_arg: id="Opts", source=CommandLine
[        clap::parser::parser] 	Parser::push_arg_values: ["true"]
[        clap::parser::parser] 	Parser::add_single_val_to_arg: cur_idx:=1
[      clap::builder::command] 	Command::groups_for_arg: id="foo"
[        clap::parser::parser] 	Parser::get_matches_with: After parse_long_arg ValuesDone
[        clap::parser::parser] 	Parser::add_defaults
[        clap::parser::parser] 	Parser::add_defaults:iter:foo:
[        clap::parser::parser] 	Parser::add_default_value: doesn't have conditional defaults
[        clap::parser::parser] 	Parser::add_default_value:iter:foo: has default vals
[        clap::parser::parser] 	Parser::add_default_value:iter:foo: was used
[        clap::parser::parser] 	Parser::add_defaults:iter:help:
[        clap::parser::parser] 	Parser::add_default_value: doesn't have conditional defaults
[        clap::parser::parser] 	Parser::add_default_value:iter:help: doesn't have default vals
[     clap::parser::validator] 	Validator::validate
[     clap::parser::validator] 	Validator::validate_conflicts
[     clap::parser::validator] 	Validator::validate_exclusive
[     clap::parser::validator] 	Validator::validate_exclusive:iter:"foo"
[         clap::output::usage] 	Usage::create_usage_with_title
[         clap::output::usage] 	Usage::create_usage_no_title
[         clap::output::usage] 	Usage::create_help_usage; incl_reqs=true
[         clap::output::usage] 	Usage::needs_options_tag
[         clap::output::usage] 	Usage::needs_options_tag:iter: f=foo
[      clap::builder::command] 	Command::groups_for_arg: id="foo"
[         clap::output::usage] 	Usage::needs_options_tag:iter:iter: grp_s="Opts"
[         clap::output::usage] 	Usage::needs_options_tag:iter: [OPTIONS] required
[         clap::output::usage] 	Usage::get_args: incls=[]
[         clap::output::usage] 	Usage::get_args: unrolled_reqs=[]
[         clap::output::usage] 	Usage::get_args: ret_val=[]
[         clap::output::usage] 	Usage::create_help_usage: usage=clap-mre [OPTIONS]
[      clap::builder::command] 	Command::color: Color setting...
[      clap::builder::command] 	Auto
[      clap::builder::command] 	Command::color: Color setting...
[      clap::builder::command] 	Auto
error: The argument '--foo' cannot be used with one or more of the other specified arguments

Usage: clap-mre [OPTIONS]

For more information try '--help'
```
