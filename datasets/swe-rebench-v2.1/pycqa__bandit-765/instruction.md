Django's `RawSQL` raises error if you use kwargs rather than args
### Describe the bug

An `IndexError: list index out of range` error is raised if you try to run bandit `RawSQL` with keyword arguments:
```python
RawSQL(sql='{}secure'.format('no'), params=[])
```

but runs as expected on positional args:
```python
RawSQL('{}secure'.format('no'), [])
```

### Reproduction steps

```bash
1. `echo -e "from django.db.models.expressions import RawSQL\nRawSQL(sql='{}secure'.format('no'), params=[])" > /tmp/bad-bandit.py`
2. `bandit /tmp/bad-bandit.py`
3. Bandit internal error gets printed out and the security issue isn't flagged
...
```


### Expected behavior

Positional args and keyword args should both be supported

### Bandit version

1.7.1 (Default)

### Python version

3.9 (Default)

### Additional context

_No response_
