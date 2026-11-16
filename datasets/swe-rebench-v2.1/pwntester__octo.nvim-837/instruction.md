Config: ssh_aliases not capture correctly hostname with hyphen
When using the ssh_aliases configuration option, the hyphen character is not handled correctly. This causes the ssh_aliases to be ignored and the default ssh_aliases to be used instead. This issue is caused by the way the ssh_aliases configuration option is parsed. [HIDDEN]

If i have this config:

```lua
require 'octo'.setup {
  ssh_aliases = { ["github.com-work"] = "github.com" },
}
```

When i execute Octo ccommand, the ssh_aliases are not used and the default ssh_aliases are used instead. This throw an error:

<img src="https://richardhapb.s3.us-east-2.amazonaws.com/personal/gh/octos_hyphen.png" width="600" alt="hyphen issue" />

I will send a PR to fix this issue.

### Additional contract requirements

- When a configured `ssh_aliases` key contains a hyphen and matches the host in a remote URL, Octo must apply that alias rather than ignore it and use default aliases.
