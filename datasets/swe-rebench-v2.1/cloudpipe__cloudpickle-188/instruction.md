Incorrect re-definition of global variables
The global variable are not correctly handeled in the `__main__` module as they do not remain global.


### Script
```python
from cloudpickle import dumps, loads


VARIABLE = "uninitialized"


def func1():
    global VARIABLE
    print("[func1] global var id{}: {}".format(id(VARIABLE), VARIABLE))
    VARIABLE = "initialized"
    return VARIABLE


# Dump and reload the function
reloaded_f1 = loads(dumps(func1))

# The function call does not change the value of the global VARIABLE
assert reloaded_f1() == "initialized"
print(VARIABLE)

# Changing the value of VARIABLE does not affect the function
VARIABLE = 'test'
assert reloaded_f1() == "initialized"

# But redumping it changes the value
assert loads(dumps(func1))() == "initialized"
print(VARIABLE)
```

### Output
```bash
[func1] global var id140197480377584: uninitialized
uninitialized
[func1] global var id140197483839984: initialized
[func1] global var id140197480295592: test
test
```

[HIDDEN]

### Additional contract requirements

When a serialized function is unpickled, global bindings already present in its target global namespace must retain their current values. Serialized bindings absent from that namespace must become available there with their serialized values. A global assignment made by a deserialized function defined in `__main__` must update the corresponding `__main__` binding, so other functions using that namespace observe the update.
