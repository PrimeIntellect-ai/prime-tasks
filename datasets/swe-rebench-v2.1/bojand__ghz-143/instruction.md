UnixTimestamp call template in milliseconds
**Is your feature request related to a problem? Please describe.**
My GPRC interface accepts unix epoch time in milliseconds but the current call template only returns values in seconds.

**Describe the solution you'd like**
I would like an additional call template variable that returns the unix timestamp in milliseconds.

### Additional contract requirements

- The call template exposes an additional variable named `TimestampUnixMilli` whose value is the call timestamp as a Unix epoch time in milliseconds.
