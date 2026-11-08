Positional arguments do not have a help
```
Running `/work/pump --help`
Usage: /work/pump <topic> [<fields...>] [-w]

pump

Options:
  -w, --wait-for-reply
                    wait for reply
  --help            display usage information
```
```
/// pump
#[derive(Debug, FromArgs)]
struct Args {
    /// topic of message to send
    #[argh(positional)]
    topic: String,
    ...
}
```
Shouldn't positional arguments like topic and fields also have their description displayed in a section such as `Options`? If not, how would the user know the meaning of `topic` and `fields`? Thanks

### Additional contract requirements

- When help output includes positional arguments, their section heading must be exactly `Positional Arguments:`.
- In help output, place `Positional Arguments:` before `Options:`. Indent each positional argument row by two spaces, with its description starting at column 20; when an argument has no description, display only its name.
