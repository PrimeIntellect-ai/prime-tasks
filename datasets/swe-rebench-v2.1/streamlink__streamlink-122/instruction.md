Non unicode escaped API breaks the plugin
I have a problem on Streamlink 0.0.2 with Twitch plugin. Luckily I figured out what's going on and fixed my own copy of code. So I would like to share my fix though I am not sure with my decision.

My question is:
> Is it safe to assume that JSON APIs other than Twitch, use particular text encoding?


Here is some error log.
```
> streamlink.exe --player <some my player> --twitch-oauth-token <redacted> https://twitch.tv/<readacted> source
[cli][info] Found matching plugin twitch for URL https://twitch.tv/<readacted>
[plugin.twitch][info] Attempting to authenticate using OAuth token
error: 'cp949' codec can't encode character '\u011b' in position 48: illegal multibyte sequence
```

Little backgrounds.

1. Twitch API does not escape 'non-ascii' characters.
2. Twitch API does not state `charset` in the `Content-type` header. Only states MIME type `application/json`.
3. I am running Korean version of Windows 10, and the plugin tries to decode response body with OS default encoding(presumably) which is CP949 in my case.

Let me follow the code flow.

1. Twitch plugin tries to authenticate with my OAuth token, in https://github.com/streamlink/streamlink/blob/0.0.2/src/streamlink/plugins/twitch.py#L264
2. ...which is `user` method in helper class, in https://github.com/streamlink/streamlink/blob/0.0.2/src/streamlink/plugins/twitch.py#L208
3. ...which requests API with GET method, in https://github.com/streamlink/streamlink/blob/0.0.2/src/streamlink/plugins/twitch.py#L167
4. I know Twitch API returns in JSON format, so going https://github.com/streamlink/streamlink/blob/0.0.2/src/streamlink/plugins/twitch.py#L182
5. ...which tries to parse response body text in JSON, implicitly tries to decode response body from bytes to str, in https://github.com/streamlink/streamlink/blob/0.0.2/src/streamlink/plugin/api/http_session.py#L70

[HIDDEN]

### Additional contract requirements

- Parsing a JSON response that does not declare a charset must produce the same values regardless of the host's default text encoding. Such JSON may be UTF-8, UTF-16 or UTF-32 encoded (as RFC 4627 allows), and non-ASCII string values must come through intact.
- When a response declares its encoding, the JSON must be decoded using that declared encoding rather than a fallback.
