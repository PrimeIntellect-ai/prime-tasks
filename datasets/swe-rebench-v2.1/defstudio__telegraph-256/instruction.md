Custom WebHook URL
I use a local Telegram Bot server. When registering, the WebHook is installed based on the APP_URL configuration variable. But my URL inside the server starts with http://127.0.0.1:8080 (for example).

As an option, make a separate option in the configuration.

### Additional contract requirements

- Use the configuration key `custom_webhook_domain` for this option. When set to `http://foo.bar.baz`, webhook registration must use a URL beginning `http://foo.bar.baz/telegraph/` and ending `/webhook`.
