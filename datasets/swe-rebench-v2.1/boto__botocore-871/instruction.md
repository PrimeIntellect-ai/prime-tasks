RefreshableCredentials serializing without timezone info
Hey boto folks -

I'm currently implementing my own CredentialsProvider that provides RefreshableCredentials. I'm having issues with code that has been working, but recently broke. I have to wonder if either one of my dependencies got bumped (although I can't prove it) or because we just entered daylight savings.

Basically, I'm always hitting this condition:

> Credentials were refreshed, but the refreshed credentials are still expired.

To create my meta-data, I'm using the same(?) code used in botocore:
```
from datetime import datetime, timedelta
from dateutil.tz import tzlocal
expiration = datetime.now(tzlocal()) + timedelta(minutes=5)
expiration.strftime('%Y-%m-%dT%H:%M:%SZ')
```
> '2016-04-07T10:26:04Z'

[HIDDEN]

I can demonstrate this inconsistency using some of the internal boto funcs
```
from botocore.credentials import _local_now, _serialize_if_needed, _parse_if_needed
now = _local_now()
print now
serialized = _serialize_if_needed(now)
print serialized
deserialized = _parse_if_needed(serialized)
print deserialized
print now - deserialized
```
> 2016-04-07 10:24:12.336556-04:00
> 2016-04-07T10:24:12Z
> 2016-04-07 10:24:12+00:00
> 4:00:00.336556

[HIDDEN]

TL;DR
It seems like your `time_fetcher` is using a timezone aware (tzlocal) datetime, but you're losing the timezone information upon serialization, defaulting to UTC. So in my case, it's comparing EST to UTC when determining expiration time.

### Additional contract requirements

- The module `botocore.credentials` exposes a public function `create_assume_role_refresher(client, assume_role_params)`. It returns a callable that takes no arguments; calling it invokes `client.assume_role` with the supplied parameters and returns a mapping with the refreshed credential fields `access_key`, `secret_key`, `token`, and `expiry_time`.
- `expiry_time` is the `Expiration` datetime serialized with its timezone abbreviation preserved, in the format `YYYY-MM-DDTHH:MM:SS<zone>` (a UTC datetime yields `YYYY-MM-DDTHH:MM:SSUTC`).
- If the `assume_role` call fails, the returned callable raises that exception.
