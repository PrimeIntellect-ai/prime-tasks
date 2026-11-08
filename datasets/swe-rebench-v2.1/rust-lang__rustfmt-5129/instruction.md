Left behind trailing whitespace on complicated generics
The following code yields "error[internal]: left behind trailing whitespace" error on rustfmt:

```
fn foo(
    a: <u16 as intercom::type_system::ExternType<
        intercom::type_system::AutomationTypeSystem,
    >>::ForeignType,
) {}
```

[(Playground)](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=f080efcbdeb52da55894a2066d946f10)

As far as I know, this has worked in the past, but has regressed somewhere within this year (unfortunately can't pinpoint the timeframe more accurately than that). Also I believe rustfmt does manage to format that properly, but adds an extra newline _before_ the parameter.

From what I can tell, the output from rustfmt is:

```
fn foo(

    a: <u16 as intercom::type_system::ExternType<
        intercom::type_system::AutomationTypeSystem,
    >>::ForeignType,
) {}
```

(The second line has indent, but no other content.)

Unfortunately the lines are output from a proc macro and end up as top-level functions in the module. I'm using full mod paths to avoid polluting the caller scope by introducing elements with `use` statements. Although in my case I'm using rustfmt just to get nicer test output for macro expansion tests so it's not like this is breaking crate usage, just tests.

#### Meta

- rustfmt version: rustfmt 1.4.38-nightly (532d2b14 2021-12-03) and whatever playground has.
- Running with: `cargo fmt` or playground
