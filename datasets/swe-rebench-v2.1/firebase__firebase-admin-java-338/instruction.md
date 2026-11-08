Incorrect timestamp format in AndroidNotification.event_time
I think the way we format the `event_time` field on `AndroidNotification` is wrong:

https://github.com/firebase/firebase-admin-java/blob/83b7a64c103fbf20f46c04df229000529e9a8d2d/src/main/java/com/google/firebase/messaging/AndroidNotification.java#L458-L462

There seems to be couple of issues with this.

1. We are not specifying the timezone for the `SimpleDateFormat`. Therefore the resulting timestamp string is in the local timezone while the backend expects it to be in UTC.
2. The way nanoseconds are formatted seems to be wrong. For the milliseconds value `1546304523123L` this generates the string `2019-01-01T01:02:03.000000123Z`. I would expect the nanos to be formatted as `123000000` (i.e. 123 milliseconds in nanos).
