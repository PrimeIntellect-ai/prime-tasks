Solve bytes return in base.py
Reminder for myself,

[HIDDEN]
[HIDDEN]

if self.broadcast_enable and not request.slave_id:
    [HIDDEN]
    break
these are the lines in async_execute which cause there to be a bytes return
i declared async_execute as returning ModbusResponse to allow type: ignore to work on the return type. Otherwise mypy would complain a lot about this. I do not know why this code was accepted in the first place

### Additional contract requirements

- When broadcasting is enabled and a request has no slave identifier, `async_execute` must resolve to a falsy result (such as `None`) to indicate that no response is expected; it must not return a bytes sentinel.
- For normal requests, `async_execute` continues to return a `ModbusResponse`.
