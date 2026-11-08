[bug] Deleting entry raises an error
**Describe the bug**

As part of my tests, I want to temporarily remove a section of my config to ensure my application reacts properly to this section being missing.

I try `del config.some_section` which produces the following error:

```
In [1]: config
Out[1]: <dynaconf.base.LazySettings object at 0x7fe6597e4c50>

In [2]: config.database
Out[2]: <Box: {'host': 'some_host', 'port': 5431, 'user': 'postgres', 'password': 'secret', 'name': 'the_data'}>

In [3]: del config.database
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
Cell In[3], line 1
----> 1 del config.database

File ~/dev/prospect/dataworker/.venv/lib/python3.11/site-packages/dynaconf/utils/functional.py:64, in LazyObject.__delattr__(self, name)
     62 if self._wrapped is empty:
     63     self._setup()
---> 64 delattr(self._wrapped, name)

File ~/dev/prospect/dataworker/.venv/lib/python3.11/site-packages/dynaconf/base.py:300, in Settings.__delattr__(self, name)
    298 self._deleted.add(name)
    299 if hasattr(self, name):
--> 300     super().__delattr__(name)

AttributeError: 'Settings' object has no attribute 'database'

In [4]: config.database
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
Cell In[4], line 1
----> 1 config.database

File ~/dev/prospect/dataworker/.venv/lib/python3.11/site-packages/dynaconf/base.py:124, in LazySettings.__getattr__(self, name)
    122     self._setup()
    123 if name in self._wrapped._deleted:  # noqa
--> 124     raise AttributeError(
    125         f"Attribute {name} was deleted, " "or belongs to different env"
    126     )
    128 if name not in RESERVED_ATTRS:
    129     lowercase_mode = self._kwargs.get(
    130         "LOWERCASE_READ_FOR_DYNACONF",
    131         default_settings.LOWERCASE_READ_FOR_DYNACONF,
    132     )

AttributeError: Attribute database was deleted, or belongs to different env
```



**To Reproduce**

Try to delete a section of a dynaconf config object. My config object is not special, I create it using the standard method. It's an instance of `dynaconf.base.LazySettings`. The section in question do exist before I try to delete it.

**Expected behavior**

I expect the command to be successful, not throw an error, and subsequent attempts to access this section to fail as if it had never been configured in the first place.

**Environment (please complete the following information):**
 - Dynaconf Version: 3.2.4

**Comments**

It looks that there is some code written to handle deleting a section of the config but
