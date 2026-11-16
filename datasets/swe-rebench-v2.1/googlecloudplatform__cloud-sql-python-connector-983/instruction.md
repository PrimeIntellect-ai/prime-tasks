Update datetimes to aware and remove naive datetimes
```
refresh_utils.py:214: CryptographyDeprecationWarning: Properties that return a naïve datetime object have been deprecated. Please switch to not_valid_after_utc.
```

### Additional contract requirements

- Certificate expiry is read using cryptography’s UTC-aware `not_valid_after_utc` value, without emitting the deprecation warning associated with the naive expiry property.
- When a credential expiry has no timezone information, interpret it as UTC before comparing it with certificate expiry.
