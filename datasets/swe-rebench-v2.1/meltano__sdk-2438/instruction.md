bug: increment state is breaking when new_value is null
### Singer SDK Version

0.27.0

### Is this a regression?

- [ ] Yes

### Python Version

3.8

### Bug scope

Taps (catalog, state, etc.)

### Operating System

Linux-debian??

### Description


context - state is not present from backend and tap is trying full-refresh with configuration which has incremental key.

incremental state is breaking when new value is null.
[HIDDEN]

https://github.com/meltano/sdk/blob/973f245d97e34efe6c2cf279998d88daaf4d43cf/singer_sdk/helpers/_state.py#LL217C7-L217C7

### Code

_No response_

### Additional contract requirements

- When the latest record has a null replication-key value, state advancement is ignored: an existing checkpoint remains unchanged, and if no checkpoint exists, a null checkpoint is not created.
- Handling the record must not raise an error.
