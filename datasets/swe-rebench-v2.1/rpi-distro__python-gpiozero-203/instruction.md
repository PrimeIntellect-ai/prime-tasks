repr is broken for closed devices
Example interactive code:
```python
>>> from gpiozero import LED
>>> led = LED(21)
>>> led
<gpiozero.LED object on pin GPIO21, active_high=True, is_active=False>
>>> led.close()
>>> led.closed
True
>>> led
Traceback (most recent call last):
  File "gpiozero/output_devices.py", line 88, in __repr__
    self.__class__.__name__, self.pin, self.active_high, self.is_active)
  File "gpiozero/devices.py", line 323, in value
    return self._read()
  File "gpiozero/devices.py", line 245, in _read
    return self.pin.state == self._active_state
AttributeError: 'NoneType' object has no attribute 'state'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "gpiozero/output_devices.py", line 90, in __repr__
    return super(OutputDevice, self).__repr__()
  File "gpiozero/devices.py", line 330, in __repr__
    self.__class__.__name__, self.pin, self.is_active)
  File "gpiozero/devices.py", line 323, in value
    return self._read()
  File "gpiozero/devices.py", line 245, in _read
    return self.pin.state == self._active_state
AttributeError: 'NoneType' object has no attribute 'state'
```

### Additional contract requirements

- After a `GPIODevice` is closed, `repr(device)` must return exactly `<gpiozero.GPIODevice object closed>`.
- The closed representation applies to every :class:`GPIODevice` subclass, using the
  concrete class name: a closed ``LED`` must repr as exactly
  ``<gpiozero.LED object closed>`` (and likewise ``<gpiozero.<ClassName> object closed>``
  for any other subclass), rather than raising an exception.
