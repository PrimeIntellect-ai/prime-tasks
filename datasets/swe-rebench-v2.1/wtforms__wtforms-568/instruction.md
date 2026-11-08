Form errors property isn't idempotent
The 'errors' property in BaseForm isn't idempotent. In particular - if you iterate over a forms attributes using e.g. inspect.getmembers - this will cause 'errors' to change from 'None' to dict({}). And so it won't be updated if any fields add/incur errors later in processing.

At a minimum, it should treat 'None' and empty dir the same. But I don't understand why it doesn't re-calc the errors every time?
