WebhookRequest and WebhookResponse abstractions
For avoid rewriting of Webhook for different routers or environments (e.g. lambda functions) we should provide:
 - `WebhookRequest` struct
 - `WebhookResponse` struct
 - `Webhook.ServeRequest` method

### Additional contract requirements

- `WebhookRequest` must expose the data needed to handle an incoming request: `Method` (`string`), `ContentType` (`string`), `IP` (`netip.Addr`), `SecurityToken` (`string`), and `Body` (`io.Reader`).
- `(*Webhook).ServeRequest` accepts a `context.Context` and a `*WebhookRequest`, and returns a `*WebhookResponse`.
- `WebhookResponse` must expose the resulting response data through `Status` (`int`), `ContentType` (`string`), and `Body` (`[]byte`).
- When a webhook handler replies with a `sendMessage` call for chat ID `1234` and text `test`, the HTTP response body must be exactly `{"chat_id":"1234","method":"sendMessage","text":"test"}`.
