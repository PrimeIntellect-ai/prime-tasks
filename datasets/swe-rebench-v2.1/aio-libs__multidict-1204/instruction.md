Implement md.merge(other)
The method should be mimic to `md.extend()` but add only keys from `other` that are absent in `self`.

The behavior is very useful for merging aiohttp session defaults into passed headers for example.
