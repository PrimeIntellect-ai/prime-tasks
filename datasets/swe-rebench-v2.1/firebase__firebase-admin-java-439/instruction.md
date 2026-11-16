FR: FcmOptions on MulticastMessage
  * Operating System version: n/a
  * Firebase SDK version: 6.13.0
  * Library version: 6.13.0
  * Firebase Product: `messaging`

Currently `MulticastMessage` does not support `FcmOptions` on the Java SDK, in contrast with NodeJS SDK for example.

We are using `MulticastMessages` and want to take advantage of `AnalyticsLabel` in PushNotifications.

Please find a relevant PR that adds the aforementioned functionality: #439

### Additional contract requirements

- Add a public static factory method `FcmOptions.withAnalyticsLabel(String analyticsLabel)` in
  `com.google.firebase.messaging.FcmOptions` that returns a new `FcmOptions` instance containing the
  supplied analytics label.
- Add a public builder method `MulticastMessage.Builder.setFcmOptions(FcmOptions fcmOptions)` in
  `com.google.firebase.messaging.MulticastMessage.Builder` that returns the builder instance for
  chaining and assigns the supplied `FcmOptions` to the multicast message, so that the options are
  propagated to each individual `Message`.
