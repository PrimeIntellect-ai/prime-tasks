context_manager.with should handle errors in `callable`
In Python, the `with` statement will catch any exceptions occurring within its body and apply the "exit" functionality before re-raising them. I think it could be useful for `context_manager.with` to behave in a similar way.

[HIDDEN] It could look something like this:

```lua
[HIDDEN]

[HIDDEN]

[HIDDEN]
return result
```

I'm new to plenary, so it's also very possible there's a reason it wasn't implemented like this that I'm not aware of :) If we want this functionality, I'd be happy to open a PR.

### Additional contract requirements

- If `callable` raises an error, `with` must complete the applicable object or coroutine cleanup before propagating that error.
