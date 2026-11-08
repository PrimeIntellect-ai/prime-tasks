Not resilient to modification of globals
The library does not resist destructive changes of the globals. As I initially reported the issue at https://github.com/vitest-dev/vitest/issues/7024 I wanted to make you aware of the problem.

One fix, if you consider that it should be fixed, would be to [HIDDEN].

Feel free to close, if the behavior is expected.

---

_If the suggestion is relevant I can propose a fix._

### Additional contract requirements

After FakeTimers has been loaded, deleting the own properties of the global Intl object must not prevent a fake-timer clock from being created and used. After FakeTimers has been loaded, setting the global Date property to undefined must not prevent a fake-timer clock from being created and used, including its Date constructor.
