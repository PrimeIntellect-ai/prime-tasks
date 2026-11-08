Coerce function returns option of type "number" as "string"
```js
const parse = require('yargs-parser');

args = parse('--slow 5 --medium 10 --fast 15', {
    number: ['slow', 'medium', 'fast'],
    coerce: {
        'slow': val => val
    },
    configuration: {
        'parse-numbers': true // default anyway
    }
}
);
console.log(args);      // { _: [], slow: '5', medium: 10, fast: 15 }
```
