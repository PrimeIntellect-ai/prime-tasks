make_refs=False Not working as expected or breaking the _in_cycle
So reviewing a few issues here I feel like that some are originated from the root cause which is that _in_cycle reference if not working properly when make_ref is false.

First, here is a simple script of how to reproduce the issue fast and easy.

```python
import datetime
from pprint import pprint

import jsonpickle
import pytz

d1 = datetime.datetime(2020, 6, 6, 6, 6, 6, 6, tzinfo=pytz.UTC)
d2 = datetime.datetime(2020, 6, 6, 6, 6, 6, 6, tzinfo=pytz.UTC)
l = [d1, d2]
encoded_list = jsonpickle.encode(l, make_refs=False)
pprint(encoded_list)
decoded_list = jsonpickle.decode(encoded_list)
```

I have been doing some investigation, the issue happens only when `make_refs=False`.
[HIDDEN]

### Additional contract requirements

When `make_refs=False`, encountering the same object again does not by itself make that occurrence a cycle. A repeated object that is not part of a genuine cycle must retain its serializable value in the encoded output and decoded result, rather than being replaced with its representation as text. Two separately constructed, equal timezone-aware datetime values in the reproduced example must each survive the round trip as values equal to their respective inputs.
