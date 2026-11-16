`HTMLElement.style` cannot be set directly
**Describe the bug**

`HTMLElement.style` cannot be set, i.e `element.style = 'display: none'` doesn't work in happy-dom though it works in browsers (even if the `style` property is readonly according to the spec).

https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/style#setting_styles

> While this property is considered read-only, it is possible to set an inline style by assigning a string directly to the style property. In this case the string is forwarded to [CSSStyleDeclaration.cssText](https://developer.mozilla.org/en-US/docs/Web/API/CSSStyleDeclaration/cssText). Using style in this manner will completely overwrite all inline styles on the element.

**To Reproduce**

```ts
const { Window } = require('happy-dom');

const window = new Window();
const document = window.document;
const button = document.createElement('button');
button.style = 'display: none';

console.log(button.outerHTML); // "<button></button>"
```

**Expected behavior**

```ts
const button = document.createElement('button');
button.style = 'display: none';
console.log(button.outerHTML); // should display "<button style="display: none"></button>"
```

**Device:**
 - Version 7.6.0
 - Node 16.17.1
