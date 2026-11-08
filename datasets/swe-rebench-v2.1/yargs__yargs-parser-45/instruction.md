.pkgConf(), .normalize() and .array() not working well together
(Originally notified in yargs/yargs#536)

```javascript
const argv = require('yargs')
      .pkgConf('opts')
      .array('a')
      .normalize('a')
      .argv;
```
The above code paired with a package.json containing
```json
"opts": {
  "a": ["bin/../a.txt", "bin/../b.txt"]
}
```
crashes throwing `TypeError: Path must be a string. Received [ 'bin/../a.txt', 'bin/../b.txt' ]`.
