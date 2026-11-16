--version output should go to the clap::Error instead of directly to stdout
### Affected Version of clap

2.32.0

### Bug or Feature Request Summary

I'm using `get_matches_from_safe` to avoid exits and writing to stdout and stderr, because I'm using Clap not to parse arguments to the program itself, but somewhere inside the program (say, for commands submitted by connecting clients, or an internal command line interface in a gui):

```rust
let foo = app.get_matches_from_safe(client_args).map_err(|e| writeln!(client_output, "{}", e).unwrap())?;
```

This works fine, except that the output of `--version` ends up in stdout, instead of in `client_output`. It works fine for `--help`.

### Expected Behaviour Summary

I would expect the output from `--version` to not be written directly to stdout, but to end up in a `clap::Error`. This looks like the originally intended behaviour, seeing that `clap::Error::use_stderr` returns true for `ErrorKind::VersionDisplayed`.

### Actual Behaviour Summary

The version is not printed to the stream that I print the `clap::Error` to, but is always sent to stdout.

### Sample Code

```rust
extern crate clap;

use std::fmt::Write;

fn main() {
	let mut buf = String::new();

	let _ = clap::App::new("test").version("1")
		.get_matches_from_safe(&["test", "--version"])
		.map_err(|e| writeln!(&mut buf, "{}", e).unwrap());

	assert_eq!(buf, "test 1\n");
}
```

### Debug output

<details>
<summary> Debug Output </summary>

```
DEBUG:clap:Parser::propagate_settings: self=test, g_settings=AppFlags(
    (empty)
)
DEBUG:clap:Parser::get_matches_with;
DEBUG:clap:Parser::create_help_and_version;
DEBUG:clap:Parser::create_help_and_version: Building --help
DEBUG:clap:Parser::create_help_and_version: Building --version
DEBUG:clap:Parser::get_matches_with: Begin parsing '"--version"' ([45, 45, 118, 101, 114, 115, 105, 111, 110])
DEBUG:clap:Parser::is_new_arg:"--version":NotFound
DEBUG:clap:Parser::is_new_arg: arg_allows_tac=false
DEBUG:clap:Parser::is_new_arg: -- found
DEBUG:clap:Parser::is_new_arg: starts_new_arg=true
DEBUG:clap:Parser::possible_subcommand: arg="--version"
DEBUG:clap:Parser::get_matches_with: possible_sc=false, sc=None
DEBUG:clap:ArgMatcher::process_arg_overrides:None;
DEBUG:clap:Parser::parse_long_arg;
DEBUG:clap:Parser::parse_long_arg: Does it contain '='...No
DEBUG:clap:Parser::parse_long_arg: Found valid flag '--version'
DEBUG:clap:Parser::check_for_help_and_version_str;
DEBUG:clap:Parser::check_for_help_and_version_str: Checking if --version is help or version...Version
DEBUG:clap:Parser::_version:
test 1thread 'main' panicked at 'assertion failed: `(left == right)`
  left: `"\n\n"`,
 right: `"test 1\n"`', src/main.rs:12:2
```
</details>

### Additional contract requirements

- When version information is requested, the returned `clap::Error` reports `clap::ErrorKind::VersionDisplayed` as its kind.
- The formatted version text is available in the public `message` field of the returned `clap::Error`. For an app named `test` with version `1.3`, that text is `test 1.3`.
