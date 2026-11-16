Make Chat.prepare idempotent
Currently we require the chat to not be prepared when calling `await chat.prepare()`

https://github.com/Quansight/ragna/blob/7071cf4fdaae03b89c837f6034dbac217dd81d72/ragna/core/_rag.py#L187-L193

That was a reasonable choice when every chat needed to be prepared. However, now with the `MetadataFilter` (#456 and following on the `corpus-dev` branch), we have regular use cases where we the chat is already prepared:

https://github.com/Quansight/ragna/blob/3dc586fa485b79b1397e7739a2921d7992a60064/ragna/core/_rag.py#L161

https://github.com/Quansight/ragna/blob/3dc586fa485b79b1397e7739a2921d7992a60064/ragna/core/_rag.py#L247-L248

This makes it rather quirky during development where you might switch between different startegies, e.g.

```python
for input in [None, metadata_filter, documents]:
    chat = Rag().chat(input=input, ...)
    if not (input is None or isinstance(input, MetadataFilter)):
        await chat.prepare()
```

Thus, I propose we remove the error from above and just make the method a no-op in case the chat is already prepared. This has no downside for the user and avoids the extra checks.
