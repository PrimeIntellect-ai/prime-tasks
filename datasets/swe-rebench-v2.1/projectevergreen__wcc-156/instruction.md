Support Constructable Stylesheets (CSS Modules) in DOM Shim
## Summary
Now that Import Attributes are a thing, including CSS Modules as [Constructable Stylesheets](https://web.dev/articles/constructable-stylesheets), it would be good to get some basic support for this into the DOM Shim at least in some capacity.

Something at minimum like, that can shim part of the [`CSSStyleSheet`](https://developer.mozilla.org/en-US/docs/Web/API/CSSStyleSheet/CSSStyleSheet) class
```js
[HIDDEN]
```


## Details

This would help support projects like Greenwood in supporting features like being able to author using Import Attributes - https://github.com/ProjectEvergreen/wcc/issues/153

### Additional contract requirements

- The DOM shim must expose a constructible `CSSStyleSheet` with callable `replace()` and `replaceSync()` methods.
