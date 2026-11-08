the default pathname is '/'
Associate with #508

```javascript
const { Window } = require('../packages/happy-dom');
const window = new Window();

const url = 'https://www.example.com';
const u = new window.URL(url);
console.log(u.pathname);
// happy-dom: ''
// browers: '/'
```
