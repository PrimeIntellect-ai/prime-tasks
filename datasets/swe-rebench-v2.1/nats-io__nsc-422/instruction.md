nsc sign with `-K` panics if seed is provided
```bash
synadia@malaga ~/D/c/s/g/a/n/b/conf> nsc add user a -K SAAFMSZMS2DGM46QHI5B65THHEXEECUJ734IRSPYNLDIJJFEB2W6TQAHCU
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x20 pc=0x135c3e6]

goroutine 1 [running]:
github.com/nats-io/nsc/cmd/store.(*Report).updateCode(0x0, 0x166f28a)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/cmd/store/status.go:160 +0x26
github.com/nats-io/nsc/cmd/store.(*Report).Message(0x0, 0xc0001fa000, 0xc00025b3e0)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/cmd/store/status.go:177 +0x2b
github.com/nats-io/nsc/cmd.run(0x173e968, 0xc00025b3e0, 0x1659400, 0xc0001a2380, 0x173e968, 0xc00025b3e0)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/cmd/action.go:146 +0x216
github.com/nats-io/nsc/cmd.RunAction(0xc0001fa000, 0xc00025a990, 0x1, 0x3, 0x1659400, 0xc0001a2380, 0x0, 0x0)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/cmd/action.go:112 +0xa5
github.com/nats-io/nsc/cmd.CreateAddUserCmd.func1(0xc0001fa000, 0xc00025a990, 0x1, 0x3, 0x0, 0x0)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/cmd/adduser.go:72 +0x5e
github.com/spf13/cobra.(*Command).execute(0xc0001fa000, 0xc00025a900, 0x3, 0x3, 0xc0001fa000, 0xc00025a900)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/vendor/github.com/spf13/cobra/command.go:762 +0x472
github.com/spf13/cobra.(*Command).ExecuteC(0x1a409e0, 0x1f00ee8, 0x0, 0x0)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/vendor/github.com/spf13/cobra/command.go:852 +0x2fe
github.com/spf13/cobra.(*Command).Execute(...)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/vendor/github.com/spf13/cobra/command.go:800
github.com/nats-io/nsc/cmd.ExecuteWithWriter(0x17302a0, 0xc00013a010, 0xc00013a010, 0x17302a0)
        /Users/synadia/Dropbox/code/src/github.com/nats-io/nsc/cmd/root.go:185 +0x52
```

### Additional contract requirements

- When a seed is supplied with `-K` for a key that is not present in the store, the command must return an error rather than panicking.
