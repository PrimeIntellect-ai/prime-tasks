Send helper parsing error to user
If you include a helper in the helpers directory and it cannot be loaded (i.e. `require()` throws), [the error is lost](https://github.com/hapijs/vision/blob/master/lib/manager.js#L260). It would be useful to see some kind of error here, perhaps you just made a simple syntax error that needs fixing.

### Additional contract requirements

- For each helper that fails to load, call `console.warn` with a warning beginning `WARNING:` and containing `vision failed to load helper` and the helper's path (including `invalid/helpers/bad1.module` and `invalid/helpers/bad2.module` when those helpers fail).
