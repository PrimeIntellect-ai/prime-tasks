Excessively long "Usage:" line when specifying invalid option.
### Please complete the following tasks

- [x] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [x] I have searched the [open](https://github.com/clap-rs/clap/issues) and [rejected](https://github.com/clap-rs/clap/issues?q=is%3Aissue+label%3AS-wont-fix+is%3Aclosed) issues

### Rust Version

rustc 1.85.0-nightly (4363f9b6f 2025-01-02)

### Clap Version

4.5.32

### Minimal reproducible code

```rust
use clap::Parser;
#[derive(Parser, Debug)]
struct Args {
    name: String,

    #[arg(long)] hello: Option<u8>,

    #[arg(long)] count01: Vec<u8>,
    #[arg(long)] count02: Vec<u8>,
    #[arg(long)] count03: Vec<u8>,
    #[arg(long)] count04: Vec<u8>,
    #[arg(long)] count05: Vec<u8>,
    #[arg(long)] count06: Vec<u8>,
    #[arg(long)] count07: Vec<u8>,
    #[arg(long)] count08: Vec<u8>,
    #[arg(long)] count09: Vec<u8>,
    #[arg(long)] count10: Vec<u8>,
    #[arg(long)] count11: Vec<u8>,
    #[arg(long)] count12: Vec<u8>,
    #[arg(long)] count13: Vec<u8>,
    #[arg(long)] count14: Vec<u8>,
    #[arg(long)] count15: Vec<u8>,
    #[arg(long)] count16: Vec<u8>,
    #[arg(long)] count17: Vec<u8>,
    #[arg(long)] count18: Vec<u8>,
}

fn main() {
    let _args = Args::parse();
}
```


### Steps to reproduce the bug with the above code

```cargo run -- --hell```

### Actual Behaviour

```
error: unexpected argument '--hell' found

  tip: a similar argument exists: '--hello'

Usage: qqq <NAME|--hello <HELLO>|--count01 <COUNT01>|--count02 <COUNT02>|--count03 <COUNT03>|--count04 <COUNT04>|--count05 <COUNT05>|--count06 <COUNT06>|--count07 <COUNT07>|--count08 <COUNT08>|--count09 <COUNT09>|--count10 <COUNT10>|--count11 <COUNT11>|--count12 <COUNT12>|--count13 <COUNT13>|--count14 <COUNT14>|--count15 <COUNT15>|--count16 <COUNT16>|--count17 <COUNT17>|--count18 <COUNT18>>

For more information, try '--help'.
```

### Expected Behaviour

Either "Usage:" like just omitted, or minimized (like as if I specify `cargo run -- --qqqqqqq`, i.e. option not similar to anything).

```
error: unexpected argument '--hell' found

  tip: a similar argument exists: '--hello'

For more information, try '--help'.
```

---

```
error: unexpected argument '--hell' found

  tip: a similar argument exists: '--hello'

Usage: qqq <NAME> [--hello <HELLO>]

For more information, try '--help'.
```

### Additional Context

If I disable `suggestions` Cargo feature, it stops mention name of invalid option (`--hell` in this example) completely, not just omit suggestions.

```
error: unexpected argument found
```

Without `suggestions` it is overly short, with `suggestions` it is overly long.

### Debug Output

<details> <summary> Debug output </summary>

```
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.07s
     Running `target/debug/qqq --hell`
[clap_builder::builder::command]Command::_do_parse
[clap_builder::builder::command]Command::_build: name="qqq"
[clap_builder::builder::command]Command::_propagate:qqq
[clap_builder::builder::command]Command::_check_help_and_version:qqq expand_help_tree=false
[clap_builder::builder::command]Command::long_help_exists
[clap_builder::builder::command]Command::_check_help_and_version: Building default --help
[clap_builder::builder::command]Command::_propagate_global_args:qqq
[clap_builder::builder::debug_asserts]Command::_debug_asserts
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:name
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:hello
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count01
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count02
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count03
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count04
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count05
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count06
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count07
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count08
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count09
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count10
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count11
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count12
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count13
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count14
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count15
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count16
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count17
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:count18
[clap_builder::builder::debug_asserts]Arg::_debug_asserts:help
[clap_builder::builder::debug_asserts]Command::_verify_positionals
[clap_builder::parser::parser]Parser::get_matches_with
[clap_builder::parser::parser]Parser::parse
[clap_builder::parser::parser]Parser::get_matches_with: Begin parsing '"--hell"'
[clap_builder::parser::parser]Parser::possible_subcommand: arg=Ok("--hell")
[clap_builder::parser::parser]Parser::get_matches_with: sc=None
[clap_builder::parser::parser]Parser::parse_long_arg
[clap_builder::parser::parser]Parser::parse_long_arg: Does it contain '='...
[clap_builder::parser::parser]Parser::possible_long_flag_subcommand: arg="hell"
[clap_builder::parser::parser]Parser::get_matches_with: After parse_long_arg NoMatchingArg { arg: "hell" }
[clap_builder::parser::parser]Parser::did_you_mean_error: arg=hell
[clap_builder::parser::parser]Parser::did_you_mean_error: longs=["hello", "count01", "count02", "count03", "count04", "count05", "count06", "count07", "count08", "count09", "count10", "count11", "count12", "count13", "count14", "count15", "count16", "count17", "count18", "help"]
[clap_builder::parser::parser]Parser::remove_overrides: id="hello"
[clap_builder::parser::arg_matcher]ArgMatcher::start_custom_arg: id="hello", source=CommandLine
[clap_builder::builder::command]Command::groups_for_arg: id="hello"
[clap_builder::parser::arg_matcher]ArgMatcher::start_custom_arg: id="Args", source=CommandLine
[ clap_builder::output::usage]Usage::create_usage_with_title
[ clap_builder::output::usage]Usage::create_usage_no_title
[ clap_builder::output::usage]Usage::create_smart_usage
[ clap_builder::output::usage]Usage::write_arg_usage; incl_reqs=true
[ clap_builder::output::usage]Usage::write_args: incls=["hello", "Args"]
[ clap_builder::output::usage]Usage::get_args: unrolled_reqs=["name"]
[clap_builder::builder::command]Command::unroll_args_in_group: group="Args"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="name"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="hello"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count01"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count02"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count03"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count04"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count05"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count06"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count07"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count08"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count09"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count10"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count11"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count12"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count13"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count14"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count15"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count16"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count17"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count18"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group: group="Args"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="name"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="hello"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count01"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count02"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count03"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count04"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count05"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count06"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count07"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count08"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count09"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count10"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count11"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count12"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count13"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count14"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count15"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count16"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count17"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[clap_builder::builder::command]Command::unroll_args_in_group:iter: entity="count18"
[clap_builder::builder::command]Command::unroll_args_in_group:iter: this is an arg
[  clap_builder::builder::arg]Arg::name_no_brackets:name
[  clap_builder::builder::arg]Arg::name_no_brackets: val_names=[
    "NAME",
]
[ clap_builder::output::usage]Usage::create_usage_with_title: usage=Usage: qqq <NAME|--hello <HELLO>|--count01 <COUNT01>|--count02 <COUNT02>|--count03 <COUNT03>|--count04 <COUNT04>|--count05 <COUNT05>|--count06 <COUNT06>|--count07 <COUNT07>|--count08 <COUNT08>|--count09 <COUNT09>|--count10 <COUNT10>|--count11 <COUNT11>|--count12 <COUNT12>|--count13 <COUNT13>|--count14 <COUNT14>|--count15 <COUNT15>|--count16 <COUNT16>|--count17 <COUNT17>|--count18 <COUNT18>>
[clap_builder::builder::command]Command::color: Color setting...
[clap_builder::builder::command]Auto
[clap_builder::builder::command]Command::color: Color setting...
[clap_builder::builder::command]Auto
error: unexpected argument '--hell' found

  tip: a similar argument exists: '--hello'

Usage: qqq <NAME|--hello <HELLO>|--count01 <COUNT01>|--count02 <COUNT02>|--count03 <COUNT03>|--count04 <COUNT04>|--count05 <COUNT05>|--count06 <COUNT06>|--count07 <COUNT07>|--count08 <COUNT08>|--count09 <COUNT09>|--count10 <COUNT10>|--count11 <COUNT11>|--count12 <COUNT12>|--count13 <COUNT13>|--count14 <COUNT14>|--count15 <COUNT15>|--count16 <COUNT16>|--count17 <COUNT17>|--count18 <COUNT18>>

For more information, try '--help'.
```

</details>
