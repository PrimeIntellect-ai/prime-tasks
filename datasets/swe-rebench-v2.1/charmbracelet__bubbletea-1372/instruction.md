Deadlock on context cancellation (inside eventLoop)
**Describe the bug**
A context cancellation while the program is inside the message processing part of the _eventLoop_ deadlocks. It is trying to send a command into the _cmds_ channel, which no longer has any receivers. This happens because at that point the [HIDDEN], having detected the cancelled context, and the _eventLoop_ blocks indefinitely while trying to send into the stale commands channel.

May happen here:
https://github.com/charmbracelet/bubbletea/blob/6a1ebaa0ea00f482b7e1b9d3c47c3eb978e70fe9/tea.go#L463

Definitely happens here:
https://github.com/charmbracelet/bubbletea/blob/6a1ebaa0ea00f482b7e1b9d3c47c3eb978e70fe9/tea.go#L509

**To Reproduce**
Cancellation of a given _tea.WithContext(ctx)_ inside a high message pressure implementation, e.g. with 1-second interval Tick commands.

**Expected behavior**
Program exit with appropriate and timely teardown on context cancellation.

**Possible Hotfix**
[HIDDEN]

**Additional context (Stacktrace)**
```
goroutine 42 [chan send, 4 minutes]:
github.com/charmbracelet/bubbletea.(*Program).eventLoop(0xc000264140, {0x673950?, 0xc0003b8008?}, 0xc0001ae230)
        github.com/charmbracelet/bubbletea@v1.3.4/tea.go:509 +0x7f7
github.com/charmbracelet/bubbletea.(*Program).Run(0xc000264140)
        github.com/charmbracelet/bubbletea@v1.3.4/tea.go:647 +0xabc
```

### Additional contract requirements

- When the program exits after context cancellation, `Run` must return an error matching `ErrProgramKilled`.
- If context cancellation occurs while processing messages, including dispatching commands from a batch, the program must not block indefinitely and must complete teardown promptly.
