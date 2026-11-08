KeyError when trying to lookup up timezone with reverse_timezone
I'm getting the following error when running the following code (with the correct usernames):

```
import json
from geopy.geocoders import Nominatim, GeoNames

lat = 40.6997716
lon = -73.9753359

geolocator = Nominatim(user_agent="test")
tz_lookup = GeoNames(user_agent="test", username="test")
tz = tz_lookup.reverse_timezone((lat, lon))
print tz
```

```
Traceback (most recent call last):
  File "set_timezone.py", line 9, in <module>
    tz = tz_lookup.reverse_timezone((lat, lon))
  File "/usr/local/lib/python2.7/dist-packages/geopy/geocoders/geonames.py", line 301, in reverse_timezone
    return self._parse_json_timezone(response)
  File "/usr/local/lib/python2.7/dist-packages/geopy/geocoders/geonames.py", line 304, in _parse_json_timezone
    [HIDDEN]
KeyError: 'timezoneId'
```

### Additional contract requirements

- A GeoNames `reverse_timezone` lookup must not raise `KeyError` solely because a successful response omits `timezoneId`.
