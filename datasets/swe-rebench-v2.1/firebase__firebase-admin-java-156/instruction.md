FR: Expose mutable_content property in iOS Notifications API
  * Operating System version: Any
  * Firebase SDK version: 5.9.0
  * Library version: Latest
  * Firebase Product: notifications

Please provide an API for setting the `mutable_content` property for iOS in Firebase Notifications.
`com.google.firebase.messaging.Aps` class exposes some some properties like `content-available` but not `mutable_content`.

`mutable_content` property is important for processing notifications in an `UNNotificationServiceExtension`.

[Apple docs](https://developer.apple.com/library/content/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/ModifyingNotifications.html)

### Additional contract requirements

- Add a public method `Aps.Builder setMutableContent(boolean mutableContent)` to `com.google.firebase.messaging.Aps.Builder`. When `true`, the built APS dictionary contains the `mutable-content` property with the value `1`; when `false`, the `mutable-content` property is absent. The method returns the same `Aps.Builder` instance.
