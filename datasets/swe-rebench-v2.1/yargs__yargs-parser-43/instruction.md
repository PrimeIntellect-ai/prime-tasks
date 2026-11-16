array with alias not working well
```javascript
// test.js
console.log(
  require('yargs-parser')(process.argv.slice(2), {
    'alias': {
      'f': 'files'
    },
    'array': ['files']
  })
);
```

```bash
node test.js -f  // -> output: { _: [], f: [ true ], files: [ true ] } (this is broken!)
node test.js --files // -> output: { _: [], files: [], f: [] }
node test.js -f -y // -> output: { _: [], f: [], files: [], y: true }
node test.js --files -y // -> output: { _: [], f: [], files: [], y: true }
```

I think it should be a bug...
