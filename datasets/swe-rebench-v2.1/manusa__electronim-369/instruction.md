Impossible to retrieve latest Chrome version -omahaproxy.appspot.com decommissioned-
## Description

It's impossible to retrieve the latest Chrome version since omahaproxy has been decommissioned.

https://groups.google.com/a/chromium.org/g/chromium-dev/c/uH-nFrOLWtE

This is visible at startup when ElectronIM complains with `ElectronIM: No network available`

The recommended alternative is:
```
https://versionhistory.googleapis.com/v1/chrome/platforms/all/channels/all/versions/all/releases?filter=endtime>2024-01-01T00:00:00Z
```

However, this is a very slow endpoint.

Another viable solution seems to be:

```
https://versionhistory.googleapis.com/v1/chrome/platforms/linux/channels/stable/versions/all/releases?filter=endtime=none
```

Which is what powers https://chromiumdash.appspot.com/releases?platform=Linux

### Additional contract requirements

The latest Chrome version must be retrieved by requesting a `versionhistory.googleapis.com` URL. The decommissioned `omahaproxy.appspot.com` service must no longer be requested.
