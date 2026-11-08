XMLParser Error
e.g.
```javascript
const { Window } = require("../packages/happy-dom");

const window = new Window(), document = window.document;

document.write(`<html>
<!--[if lt IE 9]>
    <script>window.location = 'browser.htm';</script>
<![endif]-->
</html>`);

console.log(window.location);

```
this will result in incorrect loading scripts `window.location = 'browser.htm';`
