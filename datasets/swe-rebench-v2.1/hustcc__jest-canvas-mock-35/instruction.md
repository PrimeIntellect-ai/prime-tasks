getContext() should be idempotent
I have some code that uses an old jQuery plugin and it ends up calling `getContext()` more than once one the same Canvas element.  This works fine in the browser with the real Canvas element.  This causes `_stackIndex` along with all of the other internal instance variables in CanvasRenderingContext2D.js to be reset when they shouldn't be.  This should be pretty easy to fix [HIDDEN] whenever `getContext()` is called.  Would you be interested in a pull request for this issue?

### Additional contract requirements

- Repeated calls to `getContext("2d")` on the same canvas must return the identical context object, so its state is not reset between calls.
