Providing locales to AnonymizedFaker with a function that uses the BaseProvider crashes
### Environment Details

Please indicate the following details about the environment in which you found the bug:

* RDT version: 1.9.2, 1.10.0, 1.10.1 and probably many version before these
* Python version: Any
* Operating System: Any

### Error Description

If the `AnonymizedFaker` is given a function with no provider (eg. bothify or lexify), and it is also given locales, then it crashes during validation with the following error:
```
ModuleNotFoundError                       Traceback (most recent call last)
[<ipython-input-3-620f06e16fc2>](https://localhost:8080/#) in <cell line: 2>()
      1 from rdt.transformers.pii import AnonymizedFaker
----> 2 ht.update_transformers({'review': AnonymizedFaker(provider_name=None, function_name='bothify', locales=['en_US'])})

2 frames
[/usr/lib/python3.10/importlib/util.py](https://localhost:8080/#) in find_spec(name, package)
     92         parent_name = fullname.rpartition('.')[0]
     93         if parent_name:
---> 94             parent = __import__(parent_name, fromlist=['__path__'])
     95             try:
     96                 parent_path = parent.__path__

ModuleNotFoundError: No module named 'faker.providers.BaseProvider'
```

### Steps to reproduce

```python
import pandas as pd
from rdt import HyperTransformer

ht = HyperTransformer()
data = pd.DataFrame({
    'reviewer_name': ['Bill', 'Joe', 'Sarah'],
    'rating': [1, 2, 3],
    'review': ['This was terrible, 'Bad service', 'Meh']
})
ht.detect_initial_config(data)
from rdt.transformers.pii import AnonymizedFaker
ht.update_transformers({'review': AnonymizedFaker(provider_name=None, function_name='bothify', locales=['en_US'])})
```
