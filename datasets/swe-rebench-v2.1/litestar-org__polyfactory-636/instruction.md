Bug: handle_constrained_decimal not enforcing SQL numeric type precision properly
### Description

When using the `SQLAlchemyFactory`, constraints on `Numeric` columns are not applied correctly.

The [PostgreSQL documentation](https://www.postgresql.org/docs/current/datatype-numeric.html#DATATYPE-NUMERIC-DECIMAL) defines the following for the `Numeric` type:

> The precision of a numeric is the total count of significant digits in the whole number, that is, the number of digits to both sides of the decimal point. The scale of a numeric is the count of decimal digits in the fractional part, to the right of the decimal point. So the number 23.5141 has a precision of 6 and a scale of 4.

In our project we create a SQLAlchemy model with a bunch of columns, including a few `Numeric` columns. For one of these, we require the column to have at most 4 digits, and two decimals. Effectively, we're stating that the value should be between a float such that `(0, 100)` holds, translating into the following DDL:

```sql
add column tenor numeric(4,2)
```

Since the `Numeric` type doesn't allow specifying greater than or less than values, we expect this constraint would translate to the factory, accurately following the spec. While the numeric precision and digits translate to the correct `Constraint`, that `Constraint` isn't applied accurately for `SQLAlchemyFactory` factories: `max_digits` (which is mapped to `precision`) is applied only to the part before the decimal point.

[HIDDEN] Therefore, we can end up with `Decimal`s that are outside of the `Numeric` constraints that we expect based on the SQL spec.

A workaround that I currently employed in our codebase is that for the explicit fields where this is causing flaky behavior, I manually set a minimum and maximum value so that the generated `Decimal` is correct. However, since `Numeric` doesn't allow specifying greater or lesser than values, this leads to increased overhead.

Please see below working example.

### URL to code causing the issue

_No response_

### MCVE

```python
from decimal import Decimal
from polyfactory.factories.sqlalchemy_factory import SQLAlchemyFactory
from sqlalchemy import Numeric
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.orm import Mapped
from sqlalchemy.orm import mapped_column

class Base(DeclarativeBase):
    pass

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    some_field: Mapped[Decimal] = mapped_column(Numeric(precision=4, scale=2))

class UserFactory(SQLAlchemyFactory[User]):
    ...

def test_some_field_constraint() -> None:
    # Run this test 1000 times to make it more likely the random number does not meet the constraints
    for _ in range(1000):
        user_instance = UserFactory.build()
        if user_instance.some_field >= float(100.00):
            print(user_instance.some_field)

test_some_field_constraint()
```

This will in most cases print out at least a few floats that are greater than the constraints specify:

```
100.4
100.4
101.3
100.1
101.4
100.5
100.8
101.3
100.5
100.9
100.4
101.5
100.1
```

### Steps to reproduce

```bash
The above example is self-contained and can be run as-is, e.g. in a Jupyter notebook.
```

### Screenshots

_No response_

### Logs

```bash

```

### Release Version

polyfactory==2.18.1
python==3.12.3

### Platform

- [x] Linux
- [ ] Mac
- [ ] Windows
- [ ] Other (Please specify in the description above)
