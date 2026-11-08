Bug: `time` and `UUID` fields return string instead of the expected types
### Description

If `datetime.time` or `uuid.UUID` is specified as the type in a dataclass or typeddict then the field doesn't get an instance of `datetime.time` or `uuid.UUID` as expected. The field gets a string instead. This is due to `faker.time()` and `faker.uuid4()` returning strings.

### URL to code causing the issue

_No response_

### MCVE

```python
from dataclasses import dataclass
from uuid import UUID
from datetime import time

from polyfactory.factories import DataclassFactory

@dataclass
class Foo:

    t: time
    uuid: UUID

class FooFactory(DataclassFactory):

    __model__ = Foo


foo = FooFactory.build()

# NOTE: Both assertions fail.
assert isinstance(foo.t, time)
assert isinstance(foo.uuid, UUID)
```


### Steps to reproduce

```bash
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error
```


### Screenshots

"In the format of: `![SCREENSHOT_DESCRIPTION](SCREENSHOT_LINK.png)`"


### Logs

_No response_

### Litestar Version

2.1.1

### Platform

- [X] Linux
- [ ] Mac
- [ ] Windows
- [ ] Other (Please specify in the description above)
