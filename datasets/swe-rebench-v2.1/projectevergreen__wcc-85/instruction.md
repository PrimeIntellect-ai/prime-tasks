assumed methods and members of custom element classes break the compiler
## Type of Change

<!-- Delete what does not apply -->

- Bug

## Summary
Through the compiler, we are assuming methods like `connectedCallback` and `attachShadow` which means any custom element that does not define these will break.
```js
async function initializeCustomElement(elementURL, tagName, attrs = []) {
  ...

  await elementInstance.connectedCallback(); // what if the element does not define this method???

  return elementInstance;
}
```

## Details
Basically, something like this "should" work just fine
```js
export default class Empty extends HTMLElement { }

customElements.define('x-empty', Empty)
```

 But the compiler will give errors instead
 ```sh
 # missing `attachShadow`
<template shadowroot="${this.shadowRoot.mode}">
                                                ^
TypeError: Cannot read property 'mode' of null
    at Footer.getInnerHTML (file:///Users/owenbuckley/Workspace/github/repos/wcc/lib/dom-shim.js:68:49)
    at renderComponentRoots (file:///Users/owenbuckley/Workspace/github/repos/wcc/lib/wcc.js:24:48)
    at async renderToString (file:///Users/owenbuckley/Workspace/github/repos/wcc/lib/wcc.js:101:21)
    at async file:///Users/owenbuckley/Workspace/github/repos/wcc/ssg.js:16:28
error Command failed with exit code 1.
```

----

I'm not sure what the exact behavior should be or what can be assumed, but at the very least we should be able to handle gracefully, similar to #78 .
