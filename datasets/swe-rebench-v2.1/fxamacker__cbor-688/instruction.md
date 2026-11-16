feature: Add TimeRFC3339NanoUTC option for encoding to CBOR time (tag 0)
This feature was suggested by @ssanderson at:
- https://github.com/fxamacker/cbor/issues/656#issuecomment-2847684876

Currently, we have `TimeRFC3339Nano` option for encoding to CBOR time (tag 0) with nanosecond precision.  However, it retains the timezone of time.Time being encoded and it can be inconvenient to set `time.Time` to UTC before encoding it to CBOR.

### RFC 8949 and Time

RFC 8949 defines CBOR tag 0 and tag 1 for encoding time using integer, floating point, or string value.

Unfortunately, RFC 8949 does not define an integer representation of time with sub-second precision.

This library provides `TimeUnixMicro` to encode to floating point (CBOR tag 1).

Since floating point is a lossy format, adding `TimeUnixNano` can lead to flakier round-trip tests, etc.

### System Time and Time Function Accuracy

Using `TimeUnix` uses 1-second precision, saves space, and is faster to encode. Also, avoids creating unrealistic expectations about accuracy of system time.

System time is sometimes not as accurate as we imagine (due to OS, running inside vm, etc.). For example, see:

- https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/support-boundary-high-accuracy-time

  > Time accuracy in Windows 10 and Windows Server 2016 has been substantially improved, while maintaining full backwards NTP compatibility with older Windows versions. Under the right operating conditions, systems running Windows 10, Windows Server 2016, and newer releases can deliver 1 second (s), 50 milliseconds (ms), or 1 ms accuracy.

Also, some time-related functions might use cached time values or are affected by the OS scheduler, etc.  For example, see this [old Go issue](https://github.com/golang/go/issues/14183#issuecomment-178741222) caused by OpenBSD's `nanosleep()` & scheduler.
