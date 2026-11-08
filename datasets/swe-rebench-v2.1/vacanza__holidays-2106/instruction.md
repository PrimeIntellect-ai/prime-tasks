Columbus Day is not observed in all states
## Bug Report

### Expected Behavior

**Columbus Day** is a federal holiday that's not observed in many US states (e.g. California).

```python
>>> holidays.US(years=2024, subdiv="CA").get(date(2024, 10, 14))
>>>
```

So I believe it shouldn't be returned if `subdiv` is not provided?

```python
>>> holidays.US(years=2024).get(date(2024, 10, 14))
>>>
```

### Actual Behavior

```python
>>> holidays.US(years=2024).get(date(2024, 10, 14))
'Columbus Day'
>>>
```

### Steps to Reproduce the Problem

  1. `>>> import holidays`
  2. `>>> from datetime import date`
  3. `>>> holidays.US(years=2024).get(date(2024, 10, 14))`

### Environment

- OS: macOS 13.5
- Python version: 3.12.5
- holidays version: 0.59

### Additional Context

Perhaps I misunderstood something, shouldn't country holidays calls `holidays.US(years=2024)` return **_nationwide_** holidays? That apply to all subdivisions?
