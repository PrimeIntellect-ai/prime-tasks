Misnaming in enum
Should be `who-least-did-first`

https://github.com/SebRut/pygrocy/blob/066993de96dcae02661eb169e59dfda852a73c8f/pygrocy/grocy.py#L185

Traceback (most recent call last):
  File "/config/custom_components/grocy/__init__.py", line 227, in async_update_chores
    ] = await self.hass.async_add_executor_job(wrapper)
  File "/usr/local/lib/python3.8/concurrent/futures/thread.py", line 57, in run
    result = self.fn(*self.args, **self.kwargs)
  File "/config/custom_components/grocy/__init__.py", line 223, in wrapper
    return self.client.chores(True)
  File "/usr/local/lib/python3.8/site-packages/pygrocy/grocy.py", line 461, in chores
    chore.get_details(self._api_client)
  File "/usr/local/lib/python3.8/site-packages/pygrocy/grocy.py", line 243, in get_details
    self._init_from_ChoreDetailsResponse(details)
  File "/usr/local/lib/python3.8/site-packages/pygrocy/grocy.py", line 221, in _init_from_ChoreDetailsResponse
    self._assignment_type = Chore.AssignmentType(chore_data.assignment_type)
  File "/usr/local/lib/python3.8/enum.py", line 304, in __call__
    return cls.__new__(cls, value)
  File "/usr/local/lib/python3.8/enum.py", line 595, in __new__
    raise exc
  File "/usr/local/lib/python3.8/enum.py", line 579, in __new__
    result = cls._missing_(value)
  File "/usr/local/lib/python3.8/enum.py", line 608, in _missing_
    raise ValueError("%r is not a valid %s" % (value, cls.__name__))
ValueError: 'who-least-did-first' is not a valid AssignmentType

### Additional contract requirements

- Provide a public enumeration `AssignmentType` in module `pygrocy.grocy` with the members `NO_ASSIGNMENT`, `WHO_LEAST_DID_FIRST`, `RANDOM`, and `IN_ALPHABETICAL_ORDER`.
- Each member corresponds to the Grocy API `assignment_type` string value: `"no-assignment"`, `"who-least-did-first"`, `"random"`, and `"in-alphabetical-order"` respectively.
- A chore's public `assignment_type` property exposes the `AssignmentType` member that corresponds to the API value.
