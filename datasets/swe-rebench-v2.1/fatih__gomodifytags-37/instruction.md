:GoAddTags cannot add tags to variable defined with struct literal
(originally opened in [vim-go](https://github.com/fatih/vim-go/issues/1793))
### What did you do?
I tried to run :GoAddTags inside a variable defined with a struct literal:
```go
var thing struct{
  id int
  value string
}
```

### What did you expect to happen?
I expected struct tags to be added per usual.

### What happened instead?
I got the error message:
```
vim-go: offset is not inside a struct
```

### Configuration:

* vim-go version: v1.17

* `vimrc` you used to reproduce (use a *minimal* vimrc with other plugins disabled; do not link to a 2,000 line vimrc):
[My vimrc](https://github.com/Korede-TA/dotfiles/blob/master/.vimrc)

* Vim version (first three lines from `:version`):
VIM - Vi IMproved 8.0 (2016 Sep 12, compiled Nov 29 2017 18:37:46)
Included patches: 1-503, 505-608, 682-1283
Compiled by root@apple.com

* Go version (`go version`): go1.10.1

* Go environment (`go env`): darwin/amd64
