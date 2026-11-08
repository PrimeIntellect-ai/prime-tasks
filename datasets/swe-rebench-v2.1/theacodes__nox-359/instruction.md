nox.options.sessions ignored when --pythons is passed
**Describe the bug**

When `nox.options.sessions` is specified in `noxfile.py` and `--pythons` is passed on the command-line, the setting in the `noxfile.py` is ignored.

**How to reproduce**

```python
import nox

nox.options.sessions = ("tests",)
nox.options.pythons = ("3.9",)

@nox.session(python=("3.9", "3.10"))
def tests(session):
    pass

@nox.session(python=("3.9", "3.10"))
def launch_missiles(session):
    pass
```

Run `nox --python=3.10`.

**Actual behavior**

- The tests session is run on Python 3.10.
- The launch_missiles session is run on Python 3.10.

```
nox > Running session tests-3.10
nox > Creating virtual environment (virtualenv) using python3 in .nox/tests-3-10
nox > Session tests-3.10 was successful.
nox > Running session launch_missiles-3.10
nox > Creating virtual environment (virtualenv) using python3 in .nox/launch_missiles-3-10
nox > Session launch_missiles-3.10 was successful.
nox > Ran multiple sessions:
nox > * tests-3.10: success
nox > * launch_missiles-3.10: success
```

**Expected behavior**

- The tests session is run on Python 3.10.
- The launch_missiles session is not run at all.

```
nox > Running session tests-3.10
nox > Creating virtual environment (virtualenv) using python3 in .nox/tests-3-10
nox > Session tests-3.10 was successful.
```

**Discussion**

This is a follow-up to #356, which has an associated pull request in #357.

When `--pythons` was introduced, the merge logic for `--sessions` and `--keywords` was extended to the new `--pythons` option. This means that if any of these options are specified on the command line, the corresponding settings in the `noxfile.py` are ignored. This is achieved by a custom merge function `session_filters_merge_func`, which ensures that `noxfile.py` is ignored for all of these options if any of them are set on the command-line.

In the case of `--sessions` and `--keywords`, this makes sense, because these options are different means to achieve the same goal of specifying which sessions should run. For example, if `noxfile.py` contains `nox.options.keywords = "not launch_missiles"`, we want the user to still be able to trigger the session explicitly using `--session=launch_missiles`; the custom merge function achieves that. Without the custom merge function, the user would be forced to use `--keywords` instead of `--sessions`.

In the case of `--pythons`, I would argue that this behavior is less useful. While it is true that the `--pythons` option, just like the other two options, ultimately results in filtering the session manifest, the new option is particularly useful in combination with the other options, not as a way to override them. Unlike `--sessions` and `--keywords`, it is not possible to use `--pythons` to completely control which sessions are selected. Therefore it makes less sense to me to completely ignore the other options when `--pythons` is passed.

I would also argue that the current behavior violates the principle of least surprise. The example above demonstrates this: While the `noxfile.py` clearly states the intent that `launch_missiles` should only run on explicit user request, it is enough to specify a Python version on the command line to trigger the session, without specifying the session itself.

In my opinion, the merge logic for `--pythons` should be decoupled from that of `--sessions` and `--keywords`. This would change current behavior in two ways:

- The `nox.options.sessions` and `nox.options.keywords` settings would no longer be ignored when `--pythons` is passed on the command-line.
- The `nox.options.pythons` would no longer be ignored when `--sessions` or `--keywords` are passed on the command-line.

(The second point will make it possible to run specific sessions using `-s` or `-k` without having to repeat `nox.options.pythons` on the command-line.)

**Proposed solution**

As a fix, I would propose the following two changes, in addition to the change proposed in #357:

[HIDDEN]

### Additional contract requirements

- Passing `--python` must not by itself disable the session or keyword restrictions configured in `noxfile.py`.
- Passing `--session` or `--keywords` must not by itself disable the Python selection configured by `nox.options.pythons`.
