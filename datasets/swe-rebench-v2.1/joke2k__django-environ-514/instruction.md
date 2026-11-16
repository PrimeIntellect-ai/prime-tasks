Add support for channels configuration
Would be great to have support for [channel layer configuration](https://channels.readthedocs.io/en/latest/topics/channel_layers.html?highlight=configuration#configuration) in `django-environ` :smirk: The in-memory channel layer config is pretty simple. The [channel_redis config](https://github.com/django/channels_redis/#usage) one is more interesting.

### Additional contract requirements

- Add a public class method `Env.channels_url_config(url, backend=None)` in the `environ` package. It parses a Django Channels connection URL into the configuration dictionary expected by Django Channels.
- `url` may be given either as a string or as a `urllib.parse.ParseResult`.
- `backend` is an optional explicit channel layer class path. When it is omitted, the backend is inferred from the URL scheme.
- The returned mapping contains a `BACKEND` key whose value is the dotted path of the channel layer class.
- The recognized schemes map to these channel layer classes: `inmemory` to `channels.layers.InMemoryChannelLayer`, `redis` to `channels_redis.core.RedisChannelLayer`, and `redis+pubsub` to `channels_redis.pubsub.RedisPubSubChannelLayer`.
- For the Redis-based schemes the returned mapping also contains a `CONFIG` dict with a `hosts` list of normalized Redis URLs.
- An unknown scheme raises `ImproperlyConfigured`.
