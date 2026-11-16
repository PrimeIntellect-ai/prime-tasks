new `mockPrototype(win)` implementation can cause `TypeError`
I am running into an issue when upgrading to [`2.5.1`](https://renovatebot.com/diffs/npm/jest-canvas-mock/2.5.0/2.5.1) and I believe it has something to due with changes in #100.

```log
...
client:test: TypeError: Cannot read properties of undefined (reading 'prototype')
client:test:  ❯ mockPrototype ../../node_modules/.pnpm/jest-canvas-mock@2.5.1/node_modules/jest-canvas-mock/lib/mock/prototype.js:37:50
client:test:  ❯ Proxy._default ../../node_modules/.pnpm/jest-canvas-mock@2.5.1/node_modules/jest-canvas-mock/lib/window.js:61:26
client:test:  ❯ src/setupTests.ts:31:22
client:test:      [29](<code-under-test>/actions/runs/5090740096/jobs/9149933044?pr=1141#step:8:30)| ] as const;
client:test:      [30](<code-under-test>/actions/runs/5090740096/jobs/9149933044?pr=1141#step:8:31)|
client:test:      [31](<code-under-test>/actions/runs/5090740096/jobs/9149933044?pr=1141#step:8:32)| const canvasWindow = getCanvasWindow({ document: window.document });
client:test:        |                      ^
client:test:      [32](<code-under-test>/actions/runs/5090740096/jobs/9149933044?pr=1141#step:8:33)|
client:test:      [33](<code-under-test>/actions/runs/5090740096/jobs/9149933044?pr=1141#step:8:34)| apis.forEach((api) => {
...
```

looking at [the test case](https://github.com/hustcc/jest-canvas-mock/blob/master/__tests__/mock/window.js), it only covers when there is a wellformed window object.

Not sure what the expected behavior when something other than a wellformed window object is; however I was not seeing the above error in `2.5.0` and below. There seems to some delta between the global objects (`HTMLCanvasElement`, etc.) and this newly passed window object.

currently failing line: https://github.com/hustcc/jest-canvas-mock/blob/master/src/mock/prototype.js#L37

```js
...
  win.HTMLCanvasElement.prototype.getContext = getContext2D;
...
```

---

## suggestion

[HIDDEN]

drawbacks, this potentially might be masking something in a project where the user expects the browser to behave one way; and due to all this mocking abstraction it behaves differently during testing. I think this is acceptable since, we are already basically doing this now, it just will behave slightly differently with the proposed suggestion than it does now, so I wanted to call it out.

_Originally posted by @virtuoushub in https://github.com/hustcc/jest-canvas-mock/issues/100#issuecomment-1564406609_

### Additional contract requirements

Providing a window-like object without an `HTMLCanvasElement.prototype` must not make canvas mock setup throw; the canvas method mocks remain available on the global canvas prototype. Providing a window-like object with an `HTMLCanvasElement.prototype` must continue to install the canvas method mocks on that supplied prototype.
