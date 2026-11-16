2.6.0 filters telegrams from KNX gateway/tunnel device itself
**Description of problem:**

Since xknx 2.6.0, xknx no longer recieves/processes telegrams originating from the KNX gateway itself.
A RTU modbus device is connected directly to the gateway, which is why the packets originates from the gateway itself (address 1.1.255)
Other telegrams from the KNX/TP bus are received fine through the gateway.

- [X] using xknx standalone
- [X] using Home-Assistant knx integration

**Version information:**
- xknx / Home-Assistant release with the issue: xknx 2.6.0
- last working xknx / Home-Assistant release (if known): xknx 2.5.0

**KNX installation:**
Using a SE SpaceLYnk gateway, with a modbus based power meter connected. The gateway exposes the modbus data via KNX address 1/1/4 as a 4byte_float.
Other devices connected to the gateway over KNX/TP are unaffected by the update to 2.6.0 and still work.

Using https://github.com/XKNX/xknx/blob/main/examples/example_telegram_monitor.py to compare the versons.
With 2.5.0 i see telegrams from the modbus device, on 2.6.0 i don't.

Adding debug logging to the same script shows the frames being recieved, but ignored on 2.6.0:
`DEBUG:xknx.cemi:Ignoring own CEMI: <CEMIFrame code="L_DATA_IND" src_addr="IndividualAddress("1.1.255")" dst_addr="GroupAddress("1/1/4")" flags="1011110011100000" tpci="TDataGroup()" payload="<GroupValueWrite value="<DPTArray value="[0xbe,0xa5,0xbb,0xb8]" />" />" />`

This change seems to be related to this commit:
https://github.com/XKNX/xknx/commit/996697ae8cce878aadfcbd95833b1fde3367008a

Is there a reason for these frames now being ignored? Is it possible to roll back this change?
