Time cannot be set via typing since v6.3.0
**Describe the bug**
Since the update to v6.3.0, we have noticed that when `minTime` is set, it is no longer possible to set the time by typing it into the input field: As soon as the input field loses focus, the time value displayed changes to the given `minTime` value.

Setting the date via typing still works just fine, as does setting the time by clicking the respective item in the selection list.

It seems that this issue is due to the changes in [this pull request](https://github.com/Hacker0x01/react-datepicker/pull/4552); in particular, when we use a custom version of `react-datepicker` [HIDDEN]

**To Reproduce**
I have prepared [a sandbox with an example datepicker](https://codesandbox.io/p/sandbox/react-datepicker-time-bug-ddgkwx?file=%2Fsrc%2FApp.tsx) that can be used to reproduce the behavior.

Steps to reproduce the behavior:

1. Click into the input field.
2. Replace the current time displayed with any other value (e.g. `10:00`)
3. Click outside of the input field.
4. The time displayed changes to `06:00`, which corresponds to the `minTime` value set in the example.

**Expected behavior**
The time displayed should be the time that the user typed in.
