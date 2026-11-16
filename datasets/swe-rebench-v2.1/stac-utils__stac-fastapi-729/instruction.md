`make_dataclass` erase the `__post_init__` method
in #714 we changed how we create GET request model from using `attrs` to `dataclass`. This was to support `alias` with `-`.  The downside was that we need to do `validation/conversion` in a `__post_init__` method.

It seems that this wasn't well tested 😢, and now when we create a Model with `extensions` the `__post_init__` is not ran 😭 😭 😭 😭 😭

```python
from stac_fastapi.api.models import create_get_request_model
from stac_fastapi.extensions.core import FieldsExtension

model = create_get_request_model(extensions=[FieldsExtension()])
model(datetime="yo")


model = create_get_request_model(extensions=[])
model(datetime="yo")

>> HTTPException: 400: Invalid RFC3339 datetime.
```

### where

https://github.com/stac-utils/stac-fastapi/blob/494e485c5d619d8c800bc845c391dfdced21fb2a/stac_fastapi/api/stac_fastapi/api/models.py#L28-L50
