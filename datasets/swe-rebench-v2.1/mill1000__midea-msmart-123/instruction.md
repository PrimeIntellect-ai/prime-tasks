Ignore "capability" responses (0xB5) with a frame type of 0x05
Originally noticed in the debug log from this post.

> [midea_msmart.debug_3.log](https://github.com/mill1000/midea-ac-py/files/15209814/midea_msmart.debug_3.log)

_Originally posted by @v1k70rk4 in https://github.com/mill1000/midea-ac-py/issues/122#issuecomment-2094145935_

The log contains the following bit of interest
```
2024-05-04 15:11:14.231 DEBUG (MainThread) [msmart.lan] Received response from 192.168.1.60:6444: aa12ac00000000000205b50110060101bda808
...
2024-05-04 15:11:14.373 DEBUG (MainThread) [msmart.device.AC.command] Capabilities response payload: b50110060101bd
2024-05-04 15:11:14.374 WARNING (MainThread) [msmart.device.AC.command] Unknown capability. ID: 0x 610, Size: 1.
2024-05-04 15:11:14.374 DEBUG (MainThread) [msmart.device.AC.command] Raw capabilities: {}
...
2024-05-04 15:11:14.374 DEBUG (MainThread) [msmart.device.AC.device] Ignored unknown response from 192.168.1.60:6444: b50110060101bd
```

The response was ignored, but we should have never processed it as a capabilities response. Based on the Lua, it looks like some special case property response, but the ID 0x610 is not handled by the Lua.

The log contains additional entries with known property IDs.
```
2024-05-04 15:11:59.388 DEBUG (MainThread) [msmart.device.AC.command] Capabilities response payload: b50310060101090001010a000101dc
2024-05-04 15:11:59.389 WARNING (MainThread) [msmart.device.AC.command] Unknown capability. ID: 0x 610, Size: 1.
2024-05-04 15:11:59.389 DEBUG (MainThread) [msmart.device.AC.command] Raw capabilities: {'swing_vertical_angle': True, 'swing_horizontal_angle': True}
2024-05-04 15:11:59.390 DEBUG (MainThread) [msmart.device.AC.device] Ignored unknown response from 192.168.1.60:6444: b50310060101090001010a000101dc
```

Likely this message is some kind of property update notification.
