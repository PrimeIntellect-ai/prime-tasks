Make NON_TASK match 'done'
I originally decided that statuses of type `NON_TASK` should not match either `done` nor `not done`.

But I've decided in retrospect that this was a bad idea for various reasons.

- All the other filters could match `NON_TASK` statuses, so It made `done` and `not done` unnecessarily inconsistent
- It also was a needless inconsistency with earlier releases
- Users might reasonably expect the following query to find all tasks, but it would omit any `NON_TASK` tasks:

```text
(done) OR (not done)
```

So I have now decided to make `done` also match `NON_TASK` tasks.
