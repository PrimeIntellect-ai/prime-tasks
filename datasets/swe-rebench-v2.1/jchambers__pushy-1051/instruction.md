add attributes-type and attributes to the payloadbuilder
In the [documentation for remote starting a live activity](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications#Construct-the-payload-that-starts-a-Live-Activity) it is mentioned that the attributes and attributes-type keys should be present in the payload when starting a live activity. These are not available in the payload builder yet.

### Additional contract requirements

- Add a public method `setAttributesType(String attributesType)` to `com.eatthepath.pushy.apns.util.ApnsPayloadBuilder` that returns the same `ApnsPayloadBuilder` instance. A non-null value is serialized into the payload under the key `"attributes-type"`; a null value causes that key to be omitted.
- Add a public method `setAttributes(Map<String, Object> attributes)` to `com.eatthepath.pushy.apns.util.ApnsPayloadBuilder` that returns the same `ApnsPayloadBuilder` instance. A non-null map is serialized into the payload under the key `"attributes"`; a null map causes that key to be omitted.
