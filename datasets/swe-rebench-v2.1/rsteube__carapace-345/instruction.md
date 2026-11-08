powershell: commandline not truncated to cursor position
commandline currently not truncated to cursor position so
```sh
example acti<TAB> positional1
```

is passed as
```sh
2021/05/27 16:32:12 powershell [/home/rsteube/go/bin/example _carapace powershell _ example acti positional1]
```

so previous words can't be completed
