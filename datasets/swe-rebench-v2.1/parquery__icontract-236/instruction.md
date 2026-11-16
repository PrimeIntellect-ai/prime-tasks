Missing arg for ViolationError in python 3.10
Minimal working example in `/tmp/spam.py`:

```python
from icontract import require, ViolationError


@require(lambda _ARGS: bool([s for s in _ARGS]))
def spam(*args):
    pass


if __name__ == '__main__':
    try:
        spam(*[])
    except ViolationError:
        print(bool([s for s in []]))
```

Expected behavior (python `3.9`):

```shell
$ python --version
Python 3.9.7
$ python -m pip freeze | grep icontract
icontract==2.5.5
$ python /tmp/spam.py
False
```

False behavior (python `3.10`):

```shell
$ python --version
Python 3.10.0
$ python -m pip freeze | grep icontract
icontract==2.5.5
$ python /tmp/spam.py
Traceback (most recent call last):
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_checkers.py", line 181, in _create_violation_error
    msg = icontract._represent.generate_message(contract=contract, resolved_kwargs=resolved_kwargs)
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_represent.py", line 542, in generate_message
    repr_vals = repr_values(
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_represent.py", line 463, in repr_values
    recompute_visitor.visit(node=lambda_inspection.node.body)
  File "/usr/lib/python3.10/ast.py", line 410, in visit
    return visitor(node)
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_recompute.py", line 577, in visit_Call
    args.append(self.visit(node=arg_node))
  File "/usr/lib/python3.10/ast.py", line 410, in visit
    return visitor(node)
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_recompute.py", line 882, in visit_ListComp
    result = self._execute_comprehension(node=node)
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_recompute.py", line 807, in _execute_comprehension
    code = compile(source=module_node, filename='<ast>', mode='exec')
TypeError: required field "posonlyargs" missing from arguments

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/tmp/spam.py", line 11, in <module>
    spam(*[])
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_checkers.py", line 628, in wrapper
    violation_error = _assert_preconditions(
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_checkers.py", line 290, in _assert_preconditions
    exception = _create_violation_error(contract=contract, resolved_kwargs=resolved_kwargs)
  File "/tmp/venv/lib/python3.10/site-packages/icontract/_checkers.py", line 192, in _create_violation_error
    raise RuntimeError(''.join(parts)) from err
RuntimeError: Failed to recompute the values of the contract condition:
File /tmp/spam.py, line 4 in <module>:
lambda _ARGS: bool([s for s in _ARGS])
```
