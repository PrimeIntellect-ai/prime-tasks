All nodes are renderable
I was looking to fix: https://github.com/lightning-js/renderer/issues/463 and noticed it wasn't happening any longer in main. This is because all nodes are now renderable due to
https://github.com/lightning-js/renderer/blob/main/src/core/CoreNode.ts#L771

Every node is being given a texture making it renderable. I assume you don't want that to be the case as every container node is now being rendered.

For instance:
```js
const yellowRect = renderer.createNode({
    x: 300,
    y: 0,
    width: 100,
    height: 100,
    color: 0x00000000,
    parent: testRoot,
  });
```
Gets the defaultTexture, even though it shouldn't be rendered.
