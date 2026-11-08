Robot classes don't allow pwm=False
I'm trying to use MockPin to test a robot script but I can't disable PWM:

``` python
>>> robot = Robot((1, 2), (3, 4), pwm=False)
TypeError: __init__() got an unexpected keyword argument 'pwm'
>>> robot = CamJamKitRobot(pwm=False)
TypeError: __init__() got an unexpected keyword argument 'pwm'
```

I can create motors with `pwm=False`, and I don't believe there's any reason I shouldn't be able to do the same for Robots.
