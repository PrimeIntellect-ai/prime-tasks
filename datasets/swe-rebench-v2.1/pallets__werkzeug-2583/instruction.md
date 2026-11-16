default `part_isolating=False` if the converter regex contains a `/`
Users didn't know about the `Converter.part_isolating` change as part of the router speedup, so custom converters that matched slashes stopped working. It should be possible to detect whether it should be disabled in most cases, so users won't need to know about it.

If a converter's `regex` has a `/`, we can assume it should set `part_isolating = False` by default. This default can still be overridden by setting `part_isolating` manually.

[HIDDEN]

This is a little too aggressive, as a regex could have something like `[^/]`, but that's unlikely since that's already something the router itself is handling, and the router will still work if a converter sets it `False` when it doesn't need to.

Originally discussed in https://github.com/pallets/werkzeug/issues/2506#issuecomment-1238375362
