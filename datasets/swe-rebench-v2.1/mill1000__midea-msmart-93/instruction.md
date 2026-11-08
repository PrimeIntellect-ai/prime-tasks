Improve temperature sensor resolution
Some units are capable of reporting additional temperature sensor precision in byte 15 of the StateResponse message.

e.g.
```
Byte                       11 12 13 14 15 16
c00188647f7f00 00 00 00 00 63 45 0c 00 56 19 00000000000002
```

The indoor temperature is the lower nibble, outdoor temperature the upper nibble.

Temperature is calculated as `T = Base + X/10` where X is the value in the associated nibble
