Unable to set options to zero or empty string via command line
This is with version 4.0.1.

Try with `index.js`:
```js
const convict = require('convict');
const config = convict({foo: {default: 'bar', arg: 'foo'}});
console.log(config.get('foo'));
```
and
```
>node index.js --foo 0
bar
>node index.js --foo 1
1
>node index.js --foo ""
bar
>node index.js --foo " "
<space>
```
