[Bug Report] random_demo broke after the termination/truncation update
**Describe the bug**
the `random_demo` raise an error due to how the env.last API changed.
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File ".../python3.9/site-packages/pettingzoo/utils/random_demo.py", line 18, in random_demo
    obs, reward, done, _ = env.last()
ValueError: too many values to unpack (expected 4)
```

**Code example**
```python
>>> from pettingzoo.utils import random_demo
>>> from pettingzoo.classic import tictactoe_v3
>>> random_demo(tictactoe_v3.env())
     |     |
  -  |  -  |  -
_____|_____|_____
     |     |
  -  |  -  |  -
_____|_____|_____
     |     |
  -  |  -  |  -
     |     |
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/tmp/fix-pettingzoo/.venv/lib/python3.10/site-packages/pettingzoo/utils/random_demo.py", line 18, in random_demo
    obs, reward, done, _ = env.last()
ValueError: too many values to unpack (expected 4)
>>>
```

**System Info**
Describe the characteristic of your environment:
 * Describe how Gym was installed (pip, docker, source, ...): pip
 * Operating system: linux
 * Python version: 3.9-3.10

### Checklist

- [X] I have checked that there is no similar [issue](https://github.com/Farama-Foundation/PettingZoo/issues) in the repo (**required**)
