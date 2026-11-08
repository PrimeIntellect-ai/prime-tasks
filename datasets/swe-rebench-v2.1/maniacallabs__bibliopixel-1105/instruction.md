Builder.close() doesn't stop the drivers.
For example, when I run a 12k project from `bp`, I see this at the end:

    INFO - driver - Closing connection to: /dev/cu.usbmodem1403261
    INFO - driver - Closing connection to: /dev/cu.usbmodem2084771
    INFO - driver - Closing connection to: /dev/cu.usbmodem2084491

This never appears if I use a project builder.

Omitting the shutdown has negative results - if I run it this way a few times, eventually the 12k gets into a state where I have to power cycle it and detach the USB to get it to work again.

### Additional contract requirements

- Provide `Builder(shape, driver, **kw)` in `bibliopixel.builder.builder`; `driver` may be a driver class. `Builder.start(threaded)` starts the project and `Builder.stop()` shuts it down, cleaning up its drivers so their connections are closed.
- Provide `project(desc)` in `bibliopixel.project.project` to build a project from a description dictionary. `Project.start()` starts it and `Project.stop()` stops it.
