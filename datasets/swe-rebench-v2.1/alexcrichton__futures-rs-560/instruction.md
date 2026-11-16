Add an API for calling `poll_cancel` off task
There generally should be some way to do this (on `oneshot` or any other type w/ `poll_cancel`) as it is common to use these types to feed data into the task system from external sources.

### Additional contract requirements

- Provide `Sender::is_canceled(&self) -> bool` for oneshot senders so callers outside a task can check whether the corresponding receiver has been dropped. It returns `false` while the receiver is present and `true` after it is dropped.
