Webhook empty formdata response has unexpected format for TG
### Checklist

- [x] I am sure the error is coming from aiogram code
- [x] I have searched in the issue tracker for similar bug reports, including closed ones

### Operating system

Lambda (Linux), macOS

### Python version

3.12, 3.13

### aiogram version

3.19.0

### Expected behavior

Response into webhook should work even for empty response - for unhandled events.

### Current behavior

Response into webhook is not recognized by Telegram server, it sends the same update again and again, then stops sending webhooks at all.

### Steps to reproduce

run an echo bot only for text, use response into webhook:
```python
webhook_requests_handler = SimpleRequestHandler(
    dispatcher=dp,
    bot=bot,
    handle_in_background=False,
)
```

send a sticker / a photo / anything but text

### Code example

```python3

```

### Logs

```sh

```

### Additional information

Hi
Webhooks issue, answer into webhook doesn't work when sending an empty response, for example on an unhandled event.

Case:
- made an echo bot - responding only to text
- Sent a sticker - bot responds with an empty form date:
 + headers:
```
Content-Type multipart/form-data; boundary=webhookBoundaryvsF_aMHhspPjfOq7O0JNRg
```
 + body:
```
--webhookBoundaryvsF_aMHhspPjfOq7O0JNRg--
```
- sent one sticker.
- Telegram sent 10 updates - each time application responds with an empty, and Telegram sends an update again.

how to run: example with examples - run local webhook

debugging: run ngrok, I can see both incoming requests and responses.


Probable reason:

An empty formdata should look smth like this:
```
--webhookBoundaryvsF_aMHhspPjfOq7O0JNRg
--webhookBoundaryvsF_aMHhspPjfOq7O0JNRg--
```
it has:
- start
- end

but aiohttp builds response w/o "start"

### Additional contract requirements

- For an empty webhook response, the HTTP response must have Content-Type `application/json` and a JSON body of `{}`.
