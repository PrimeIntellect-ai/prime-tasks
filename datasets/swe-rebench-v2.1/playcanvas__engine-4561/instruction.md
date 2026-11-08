If all assets are already loaded and AssetListLoader is used to load the assets, the done callback is not called
Project: https://playcanvas.com/project/966580/overview/asset-list-all-loader-bug
Expectation: 'Done' to be printed in console

Workaround, use the ready function to set a callback.

Looks like in the `load` function, [HIDDEN]

https://github.com/playcanvas/engine/blob/main/src/asset/asset-list-loader.js#L130

### Additional contract requirements

- When all assets are already loaded, calling AssetListLoader to load them must invoke its completion callback.
