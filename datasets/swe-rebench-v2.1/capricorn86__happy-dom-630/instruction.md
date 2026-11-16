TypeError in window constructor
**Describe the bug**

```javascript
const { Window } = require('happy-dom');

const window = new Window({
    innerWidth: 1024,
    innerHeight: 768,
    url: 'http://localhost:8080',
});

console.log(window);
/*
            this.location.href = options.url;
                               ^

TypeError: Cannot set properties of undefined (setting 'href')
*/
```
