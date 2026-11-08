Expand tilde to home directory
On Linux, the following works in HTPPie:

`http -f POST example.com/files @~/.profile`

But when attempting `xh -f POST example.com/files @~/.profile`, I get "xh: error: No such file or directory (os error 2)".

It turns out the tilde is not being interpreted, and it works if I expand it manually: `xh -f POST example.com/files @/home/user/.profile`. I can also use `$HOME` so that my shell expands it for me, but I much prefer the brevity of `~`.
