Add support for "thread-id" in SimpleApnsPushNotification class
The SimpleApnsPushNotification class is missing the `thread-id` attribute, see:

https://developer.apple.com/library/content/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/PayloadKeyReference.html#//apple_ref/doc/uid/TP40008194-CH17-SW1

> Provide this key with a string value that represents the app-specific identifier for grouping notifications. The system groups notifications with the same thread identifier together in Notification Center and other system interfaces. For local notifications, this key corresponds to the threadIdentifier property of the UNNotificationContent object.

### Additional contract requirements

The `thread-id` is an attribute of the notification payload. Add a public method `setThreadId(String threadId)` to `com.relayrides.pushy.apns.util.ApnsPayloadBuilder`. When a non-null value is supplied, the APS dictionary of the generated payload includes a `"thread-id"` entry whose value is that string. When no value is supplied, no `"thread-id"` entry is present.
