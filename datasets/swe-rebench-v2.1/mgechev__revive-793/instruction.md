Panic when contains empty type block declaration
**Describe the bug**
revive panics when the source code contains
`
type ()
`

**To Reproduce**
Steps to reproduce the behavior:
1. I install revive v1.2.4
2. Write Program with `type ()` declaration
3. Run `revive -config revive.toml -formatter friendly ./...`


Panic happened in the line:
github.com/mgechev/revive@v1.2.4/rule/redefines-builtin-id.go:92

**Expected behavior**
Should not panics without any meaningful messages.


**Desktop (please complete the following information):**
 - OS: [e.g. Ubuntu 20.04]
 - go1.19.4 linux/amd64
