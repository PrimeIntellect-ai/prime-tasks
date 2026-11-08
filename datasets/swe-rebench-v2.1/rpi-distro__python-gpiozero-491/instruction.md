Can't create AngularServo with an initial_angle of None
According to the [documentation](http://gpiozero.readthedocs.io/en/latest/api_output.html#gpiozero.AngularServo) an `AngularServo` can be given an `initial_angle` of `None`.
However if you actually try this, you get

```
TypeError: unsupported operand type(s) for -: 'NoneType' and 'int'
```
