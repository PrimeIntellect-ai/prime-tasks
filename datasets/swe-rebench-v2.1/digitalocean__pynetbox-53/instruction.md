Some urls are not fully urlencoded
We had some trouble with devices that have special chars in their name, such as `#`. Here's an example:

```
>>> i =  netbox.dcim.interfaces.get(name='ipmi', device='New TwinU db #2 / D')
>>> i is None
True
```

The access log looks like this
```
"GET /api/dcim/interfaces/?name=ipmi&device=New%20TwinU%20db%20 HTTP/1.1"
```

It's clear the rest of the device name is getting cut off because the `#` was not encoded.
