Unable to turn off "breeze" modes on Breezeless device
Originally reported here https://github.com/mill1000/midea-ac-py/issues/212

@lpispek @Jarrekstar Can you try running this example?
```python3
import asyncio
import logging

from msmart.device import AirConditioner as AC

logging.basicConfig(level=logging.DEBUG)

DEVICE_IP = "YOUR_DEVICE_IP"
DEVICE_PORT = 6444
DEVICE_ID = "YOUR_AC_ID"

# For V3 devices
DEVICE_TOKEN = None  # "YOUR_DEVICE_TOKEN"
DEVICE_KEY = None  # "YOUR_DEVICE_KEY"


async def main():
    device = AC(ip=DEVICE_IP, port=6444, device_id=int(DEVICE_ID))
    if DEVICE_TOKEN and DEVICE_KEY:
        await device.authenticate(DEVICE_TOKEN, DEVICE_KEY)

    # Get device capabilities
    await device.get_capabilities()

    # Refresh the state
    print("Refreshing state")
    await device.refresh()

    # Print current breeze properties
    print({
        'breeze_away': device.breeze_away,
        "supports_breeze_away": device.supports_breeze_away,
        'breeze_mild': device.breeze_mild,
        "supports_breeze_mild": device.supports_breeze_mild,
        "breezeless": device.breezeless,
        "supports_breezeless": device.supports_breezeless,

    })

    print("Enabling Breezeless")
    device.breezeless = True
    await device.apply()

    # Print current breeze properties
    print({
        'breeze_away': device.breeze_away,
        'breeze_mild': device.breeze_mild,
        "breezeless": device.breezeless,
    })

    await asyncio.sleep(10)

    # Refresh the state
    print("Refreshing state")
    await device.refresh()

    # Print current breeze properties
    print({
        'breeze_away': device.breeze_away,
        'breeze_mild': device.breeze_mild,
        "breezeless": device.breezeless,
    })

    print("Diabling Breezeless")
    device.breezeless = False
    await device.apply()

    # Print current breeze properties
    print({
        'breeze_away': device.breeze_away,
        'breeze_mild': device.breeze_mild,
        "breezeless": device.breezeless,
    })

    await asyncio.sleep(10)

    # Refresh the state
    print("Refreshing state")
    await device.refresh()

    # Print current breeze properties
    print({
        'breeze_away': device.breeze_away,
        'breeze_mild': device.breeze_mild,
        "breezeless": device.breezeless,
    })


if __name__ == "__main__":
    asyncio.run(main())

```

### Additional contract requirements

- When parsing a properties response, emit a log message at WARNING level or higher for a failed `BREEZE_CONTROL` property matching `Property .*BREEZE_CONTROL.* failed, Result: 0x11.`.
- When no breeze mode is active, applying the device state must request the `BREEZE_CONTROL` property with the value `0x01`, since devices accept `0x01` (not `0x00`) to disable breeze modes.
