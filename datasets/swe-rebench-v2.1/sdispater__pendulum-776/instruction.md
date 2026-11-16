deepcopy on DateTime produces incorrect offset in copy during dst transition
<!--
  Hi there! Thank you for discovering and submitting an issue.

  Before you submit this; let's make sure of a few things.
  Please make sure the following boxes are ticked if they are correct.
  If not, please try and fulfill these first.
-->

<!-- Checked checkbox should look like this: [x] -->
- [x] I am on the [latest](https://github.com/sdispater/pendulum/releases/latest) Pendulum version.
- [x] I have searched the [issues](https://github.com/sdispater/pendulum/issues) of this repo and believe that this is not a duplicate.

<!--
  Once those are done, if you're able to fill in the following list with your information,
  it'd be very helpful to whoever handles the issue.
-->

- **OS version and name**: MacOS 12.0.1 Monterey
- **Pendulum version**: 2.1.2
- **Python version**: 3.11.5

Issue also presents on python 3.10.1 and python 3.10.13

## Issue
<!-- Now feel free to write your issue, but please be descriptive! Thanks again 🙌 ❤️ -->

When passing a DateTime undergoing dst transition to standard deepcopy, the produced DateTime has an invalid offset.

## Reproduction

### Code

```python
import pendulum
from copy import deepcopy

d = pendulum.from_timestamp(1699174800.0, tz="US/Pacific")

print(f"Original: {d!r}")
print(d.isoformat())
print(d.timestamp())

d2 = deepcopy(d)
print(f"Copied: {d2!r}")
print(d2.isoformat())
print(d2.timestamp())
```

### Output

```
Original: DateTime(2023, 11, 5, 1, 0, 0, tzinfo=Timezone('US/Pacific'))
2023-11-05T01:00:00-08:00
1699174800.0
Copied: DateTime(2023, 11, 5, 1, 0, 0, tzinfo=Timezone('US/Pacific'))
2023-11-05T01:00:00-07:00
1699171200.0
```

## Workaround

An ugly hack can be used to work around the issue:

```python
# UGLY HACK
from pendulum.datetime import DateTime
DateTime.__deepcopy__ = lambda d, *args: d

# Script from above
import pendulum
from copy import deepcopy

d = pendulum.from_timestamp(1699174800.0, tz="US/Pacific")

print(f"Original: {d!r}")
print(d.isoformat())
print(d.timestamp())

d2 = deepcopy(d)
print(f"Copied: {d2!r}")
print(d2.isoformat())
print(d2.timestamp())
```

Result:
```
Original: DateTime(2023, 11, 5, 1, 0, 0, tzinfo=Timezone('US/Pacific'))
2023-11-05T01:00:00-08:00
1699174800.0
Copied: DateTime(2023, 11, 5, 1, 0, 0, tzinfo=Timezone('US/Pacific'))
2023-11-05T01:00:00-08:00
1699174800.0
```

## Relevance

Deepcopy on DateTimes occurs any time dataclass' module-level `asdict` is called on a dataclass object that contains DateTime objects, triggering this bug. `asdict` in turn is called by pydantic's json encoder function `pydantic_encoder`, which is how we found out about this in the first place.

### Additional contract requirements

- Calling `copy.deepcopy()` on a `pendulum.DateTime` returns a new, distinct `DateTime` instance rather than the original object.
- The returned instance has the same year, month, day, hour, minute, second, microsecond, timezone and fold as the original, and preserves the original's UTC offset.
