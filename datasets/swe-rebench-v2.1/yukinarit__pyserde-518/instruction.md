Support for SQLAlchemy dataclass
SQLAlchemy 2.0 introduced PEP 681 support to its integration with dataclasses, but unfortunately this is implemented through a generic type `Mapped[T]` that at the moment is not correctly understood.

```python
from typing import Optional

from serde import serde, from_dict
from sqlalchemy import String, JSON
from sqlalchemy.orm import DeclarativeBase, MappedAsDataclass
from sqlalchemy.orm import Mapped
from sqlalchemy.orm import mapped_column


class Base(MappedAsDataclass, DeclarativeBase):
    pass


@serde
class User(Base):
    __tablename__ = "user"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str]
    fullname: Mapped[str] = mapped_column(String(30))
    nickname: Mapped[Optional[str]]
    meta: Mapped[Optional[JSON]] = mapped_column(type_=JSON)


user = from_dict(User, {"id": 1, "name": "john", "fullname": "John Doe"})

```
Leads to an error:
```
Traceback (most recent call last):
  File "[...]/example.py", line 25, in <module>
    user = from_dict(User, {"id": 1, "name": "john", "fullname": "John Doe"})
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "[...]/lib/python3.12/site-packages/serde/de.py", line 529, in from_dict
    return from_obj(cls, o, named=True, reuse_instances=reuse_instances)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "[...]/lib/python3.12/site-packages/serde/de.py", line 497, in from_obj
    raise SerdeError(e) from None
serde.compat.SerdeError: Unsupported type: int
```

### Additional contract requirements

- The public function `serde.init(enable: bool)` activates the Serde runtime for the process.
