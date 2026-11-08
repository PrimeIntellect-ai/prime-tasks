Regression: Garbled error message when session not found
<!-- Thank you for filing a bug! Please feel free to answer as much or as little of this template as you can. -->

**Describe the bug**
Nox prints a garbled error message when a session is not found.

More precisely, instead of the offending session name, Nox prints the representation of an AST tree.

This is a regression on the main branch, no release is affected.

**How to reproduce**
In the Nox repository, pass a bogus session name.

```python
$ nox -s bogus
nox > Error while collecting sessions.
nox > Sessions not found: Module(body=[Expr(value=Name(id='bogus', ctx=Load()))], type_ignores=[])
```

**Expected behavior**
```python
$ nox -s bogus
nox > Error while collecting sessions.
nox > Sessions not found: bogus
```
