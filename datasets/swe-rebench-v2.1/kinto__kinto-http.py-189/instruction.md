Expose methods for paginated lists
Currently there is no way to consume the content of individual pages using `get_records()`.

We could add a generator `get_paginated_records()` that would yield individual pages...

```py
for page_records in client.get_paginated_records(_limit=100):
     print(len(page_records))
```
