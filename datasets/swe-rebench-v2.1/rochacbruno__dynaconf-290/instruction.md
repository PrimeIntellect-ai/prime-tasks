[bug] RuntimeError: dictionary changed size during iteration when using @del within dynaconf_merge logic
**Describe the bug**
The following [line](https://github.com/rochacbruno/dynaconf/blob/25fed5dc27d1dd78c368d7464f7d160b46aa1d24/dynaconf/utils/__init__.py#L49
) is bugged, changing dict size during iteration, via pop() leads to

```
RuntimeError: dictionary changed size during iteration
```

**To Reproduce**
You can run following python code which is assumed to be very simple interpretation of the code line above:
```
new = {"a": 1}

for k, v in new.items():
    new.pop(k, None)
```

1. To reproduce it with `dynaconf`, use following config.yaml
```
default:
  options:
    A: 1
    B: 2
development:
  options:
    dynaconf_merge:
      B: "@del"
```

**Expected behavior**
No RuntimeError, key marked with `@del` is removed from merge result
