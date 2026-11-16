Go package: support file input
**Is your feature request related to a problem? Please describe.**
I'm looking into using [dasel package](https://daseldocs.tomwright.me/use-as-a-go-package) in my tool. As far as I can see you're supposed to unmarshal input file yourself and then use `rootNode := dasel.New(data)` to work with the data.

**Describe the solution you'd like**
Since `dasel` command already knows how to read all supported file types, it would be nice to have something like `dasel.NewFromFile(path, fileType)`.

**Describe alternatives you've considered**
Basically re-implementing everything in the [./internal](https://github.com/TomWright/dasel/blob/master/internal) folder.

**Additional context**
I need to modify various file formats in my tool and `dasel` fits the bill perfectly. With this addition it would be much easier to use `dasel` as a package.

### Additional contract requirements

Add a public function `NewFromFile(filename string, parser string) (*Node, error)` in package `dasel`. It opens the file at `filename`, selects the read parser identified by `parser` (for example `json`, `yaml`, `yml`, `toml`, `xml`, `csv`), unmarshals the file contents, and returns a new root `Node` wrapping the unmarshalled value. The parser is resolved before the file is opened, so an unknown parser is reported even when the requested file does not exist.

File-open errors must include `could not open file: open <filename>` (where `<filename>` is the requested path), and unmarshal errors must include `could not unmarshal data`. An unknown parser must produce an error whose message includes `unknown parser: <parser>`.
