ApnsPayloadBuilder generates simple alert text instead of alert dictionary
The following codesnippet:

```java
final String payload = new ApnsPayloadBuilder()
        .setAlertBody("BODY")
        .setAlertTitle("TITLE")
        .buildWithDefaultMaximumLength();
```

results in this payload:

```json
{
  "aps": {
    "alert": "BODY"
  }
}
```

My expectation would be:

```json
{
  "aps": {
    "alert": {
      "body": "BODY",
      "title": "TITLE"
    }
  }
}
```

So, if I add any property (other than alert body) to the builder, and that property belongs into the alert dictionary, then the dictionary should actually be generated.

[HIDDEN]

Best regards
Christian Charles
