support LINE accountLink event
https://developers.line.me/en/docs/messaging-api/reference/#account-link-event

### Additional contract requirements

- The `LineEvent` class in `src/context/LineEvent.js` exposes a public `isAccountLink` getter that returns `true` when the event type is `'accountLink'`, and `false` otherwise.
- The `LineEvent` class in `src/context/LineEvent.js` exposes a public `accountLink` getter that returns the account-link payload `{ result: 'ok' | 'false', nonce: string }` for an `'accountLink'` event, and `null` for any other event type.
