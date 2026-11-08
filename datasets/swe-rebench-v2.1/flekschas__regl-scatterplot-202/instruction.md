Disable zoom and pan
Is there a way to disable zoom and pan? Can't find this in the documentation or the source code.

### Additional contract requirements

- `createScatterplot(options)` accepts a `cameraIsFixed` boolean option. Its default value is `false`. When `cameraIsFixed` is `true`, mouse-wheel zoom and pan interactions do not change the camera, while programmatic zooming (for example `zoomToOrigin()` and `zoomToPoints()`) still works.
- `scatterplot.get('cameraIsFixed')` returns the current fixed-camera flag as a boolean.
- `scatterplot.set({ cameraIsFixed })` updates the fixed-camera flag at runtime, toggling whether mouse-wheel zoom and pan affect the camera.
- The module `src/constants` exports a named constant `DEFAULT_CAMERA_IS_FIXED` whose value is `false`.
