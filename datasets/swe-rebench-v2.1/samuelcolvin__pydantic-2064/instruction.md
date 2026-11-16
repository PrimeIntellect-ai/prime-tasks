json_encoders inheritance
# Feature Request

Currently, defining `json_encoders` in child classes completely overrides the one defined from the parent classes:
```py
from datetime import datetime, timedelta
from pydantic import BaseModel

class A(BaseModel):
    dt: datetime = datetime.now()
    class Config:
        json_encoders = {datetime: lambda _: "encoded_from_A"}

print(A().json())
#> {"dt": "encoded_from_A"}
class B(A):
    timedt: timedelta = timedelta(hours=100)
    class Config:
        json_encoders = {timedelta: lambda _: "encoded_from_B"}

print(B().json())
#> {"dt": "2020-10-23T01:11:20.613624", "timedt": "encoded_from_B"}

```

I think it would be handy to merge the JSON encoders with the one defined in the parent ones, thus the result would be:
```py
print(B().json())
#> {"dt": "encoded_from_A", "timedt": "encoded_from_B"}
```

As an extension, it should still be possible to override the parent ones:
```py
class Bbis(A):
    timedt: timedelta = timedelta(hours=100)

    class Config:
        json_encoders = {
            datetime: lambda _: "encoded_from_Bbis",
            timedelta: lambda _: "encoded_from_Bbis",
        }

print(Bbis().json())
#> {"dt": "encoded_from_Bbis", "timedt": "encoded_from_Bbis"}
```

I'm eager to implement this feature if you think it's worth it :smile:

### Additional contract requirements

When JSON encoders are inherited through multiple model generations, each child retains encoders inherited by its parent for types the child does not override. The child's encoder takes precedence when both define an encoder for the same type.
