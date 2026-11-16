Error when sharing Assets between Application instances
Consider a single page displaying a gallery models/assets. There are  multiple `AppBase` instances and a single set of `Assets` shared across multiple app instances.

This [currently throws a rendering error](https://codesandbox.io/p/sandbox/7prvzh?file=%2Fsrc%2Fmain.js%3A10%2C1) presumable because resource cannot be shared. However, it's not clear for the user what is wrong, or how to fix it. If assets can't be shared we should provide better feedback and warnings

This is a real world user issue See https://github.com/playcanvas/react/issues/80

### Additional contract requirements

- A GLB container asset's resource exposes a public method `instantiateRenderEntity(options?)` that returns an `Entity`.
- The `Entity` returned by `instantiateRenderEntity()` must be associated with the `AppBase` instance whose asset registry loaded the asset; its `_app` property is that `AppBase` instance. This must hold when a single set of assets is shared across multiple `AppBase` instances, so that each instantiated entity is bound to the application that loaded the asset rather than to whichever application is currently active.
