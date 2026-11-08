The MultiplexedSessionPool.Close may be deadlocked
### Describe the bug（Bug 描述）

https://github.com/openGemini/openGemini/blob/d12680553f73abea4005ef425751854d09d60ecc/engine/executor/spdy/multiplexed_session_pool.go#L167-L173

[HIDDEN]

For example, the Close() method is repeatedly invoked.

### To Reproduce（Bug 复现步骤）

_No response_

### Expected behavior（期望结果）

_No response_

### Screenshots（屏幕截图）

_No response_

### Logs（完整的错误日志）

_No response_

### Additional context（其他的一些补充内容）

_No response_

### Additional contract requirements

- Repeated calls to `MultiplexedSessionPool.Close` must complete without deadlocking.
