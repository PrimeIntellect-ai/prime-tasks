Global middleware don't work in 12.0.1
I've tried this code:

```
const yargs = require('yargs');

const mwFunc1 = argv => console.log('I\'m a middleware function');
const mwFunc2 = argv => console.log('I\'m another middleware function');

yargs
  .command('myCommand', 'some command', {}, function(argv){
    console.log('Running myCommand!');
  })
  .middleware([mwFunc1, mwFunc2]).argv;
```


OUTPUT:
```
Running myCommand!
```

No trace of the middlewares :(
