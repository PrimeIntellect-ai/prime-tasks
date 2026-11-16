implement Camera Dismiss Event
https://developers.facebook.com/docs/messenger-platform/camera-effects#dismiss

```js
{
  "sender": {
    "id": "<PSID>"
  },
  "recipient": {
    "id": "<PAGE_ID>"
  },
  "timestamp": 1469111400000,
  "branded_camera": {
     "content_ids": [<CAMERA-EFFECT-ID>, <CAMERA-EFFECT-ID>, ...],
     "event": "dismiss"
  }
}
```

### Additional contract requirements

- Expose `MessengerEvent.isBrandedCamera` as a boolean getter that identifies a Camera Dismiss event and is false for other event types.
- Expose `MessengerEvent.brandedCamera` as a getter that returns the event’s `branded_camera` payload, including its `content_ids` and `event` values, or `null` when the event is not a branded-camera event.
