Double text in SSR when started with quote symbols
**Observed Behaviour**

Trying this code:
```js
const InfernoServer = require("inferno-server")
const createElement = require("inferno-create-element")
InfernoServer.renderToString(createElement('div', {}, '"test'))
```
Gives:
```html
<div>"test&quot;test</div>
```
Text doubles when started with `"` or `&`

**Expected Current Behaviour**

Should be
```html
<div>&quot;test</div>
```


**Inferno Metadata**
Was tested here: https://npm.runkit.com/

### Additional contract requirements

- Rendering the text `"Hello world"` inside a `div` must produce:

```html
<div>&quot;Hello world&quot;</div>
```
