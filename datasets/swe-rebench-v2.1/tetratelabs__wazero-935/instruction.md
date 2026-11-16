stdout always detected as a character device
After 78ac85cce1d `stdout` is always detected as a character device. Is this expected?
This breaks my usage of `wazero` in [RethinkRAW](https://rethinkraw.com).

**To Reproduce**

```sh
git clone --branch atty https://github.com/ncruces/wazero-bugs
cd wazero-bugs
go run main.go
```

This is the offending code in `dcraw`:
https://github.com/ncruces/dcraw/blob/8dcf1ff24ad0b5a09c8b0c1030d983c09d159284/dcraw.c#L10314-L10317

**Expected behavior**

IMO, `isatty` should not blindly return true in all cases. I'm capturing the output of a tool to a `byte.Buffer`. It's expected that it is binary. I can patch `dcraw`, but other tools (e.g. `gzip`) will similarly complain.

**Environment (please complete the relevant information):**
- Go version: go1.19.4
- wazero Version: 78ac85cce1d674c1c47c7ff2dacbfbc2e3a3e2b4
- Host architecture: amd64
- Runtime mode: compiler

### Additional contract requirements

WASI standard input, output, and error must be identified as terminal devices only when their underlying host descriptors are terminals. Captured or otherwise non-terminal streams must report false for `isatty`; terminal-backed standard streams must remain identifiable as terminals.
