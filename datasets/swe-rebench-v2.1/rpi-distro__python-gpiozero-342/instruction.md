Robot can't have its value set
AFAIK the following _should_ work, but it doesn't.
```python
>>> from gpiozero.pins.mock import MockPWMPin
>>> import gpiozero.devices
>>> gpiozero.devices.pin_factory = MockPWMPin
>>> from gpiozero import Robot
>>> r = Robot((1,2), (3,4))
>>> r.value
RobotValue(left_motor=0, right_motor=0)
>>> r.value = r.value
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/andrew/tmp_working/python-gpiozero/gpiozero/devices.py", line 299, in __setattr__
    return super(CompositeDevice, self).__setattr__(name, value)
  File "/home/andrew/tmp_working/python-gpiozero/gpiozero/devices.py", line 146, in __setattr__
    return super(GPIOBase, self).__setattr__(name, value)
AttributeError: can't set attribute
```

Just for comparison, this does work:
```python
>>> from gpiozero.pins.mock import MockPWMPin
>>> import gpiozero.devices
>>> gpiozero.devices.pin_factory = MockPWMPin
>>> from gpiozero import TrafficHat
>>> t = TrafficHat()
>>> t.value
TrafficHatValue(lights=TrafficLightsValue(red=False, amber=False, green=False), buzzer=False, button=False)
>>> t.value = t.value
```

If the Robot can't have it's `value` set, then I guess it doesn't make sense for it to use the `SourceMixin`?

### Additional contract requirements

Assigning a pair of motor speeds to `Robot.value` sets the corresponding left and right motor speeds, and the getter reflects the applied speeds. The value object returned by `Robot.value` can itself be assigned back to `Robot.value` without raising an error.
