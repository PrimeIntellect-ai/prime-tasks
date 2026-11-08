TypeError: timezone() missing required argument 'offset' when using date_time provider
Hej all,
With faker v36.2.2 on Python 3.12.0 I have an issue that might originate from the recent datetime refactoring.

The following code works
```python
from faker import Faker, providers
from datetime import timezone

fk = Faker()
Faker.seed(4321)
# fk.add_provider(providers.date_time)
# print(timezone is fk.timezone)
print(fk.timezone())
```

But when umcommenting the line with add_provider, the error indicated in the title happens.

As a workaround I can drop the date_time provider but it still might be confusing to users.

As a hint I found that `timezone is fk.timezone` weirdly is True when the provider is added, maybe something mixed up in the imports.

### Additional contract requirements

- After the date_time provider is added to a Faker instance with `add_provider()`, calling `timezone()` on that instance must still return a timezone name string instead of raising an error.
