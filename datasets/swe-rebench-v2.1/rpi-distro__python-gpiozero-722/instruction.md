"import gpiozero" shouldn't fail without a valid pin factory
The following example is a valid method of setting the pin factory to mock:

```python
import gpiozero
from gpiozero.pins.mock import MockFactory
gpiozero.Device.pin_factory = MockFactory()
```

but it only works if `import gpiozero` is successful, having found a valid pin factory.

If you're on a Raspberry Pi, that's easy - you just install rpi.gpio (even if you don't intend to use it).

If you're on a PC, the following will happen:

- rpi.gpio will fail (even if it's installed - can only be run on a Pi)
- rpio will fail (even it it's installed - can only be run on a Pi)
- pigpio will fail (even if it's installed - pigpiod not running on localhost)
- native will fail (can't access /dev/mem)

And it runs out of options.

The only way to get it to work is to set the pin factory in an environment variable.

It would be nice if you could get past `import gpiozero`, and if no pin factory is found, it's set to `None` and fails when you try to create a device. Would that be that possible?
