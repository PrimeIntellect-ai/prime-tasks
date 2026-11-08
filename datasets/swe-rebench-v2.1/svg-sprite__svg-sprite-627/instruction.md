Passing winston logger to config causes Error
```
const log = winston.createLogger();
const config = new SVGSpriterConfig({
    log,
});
```
throws
```
Uncaught TypeError: Function has non-object prototype 'undefined' in instanceof check
    at Function.[Symbol.hasInstance] (<anonymous>)
```
Because `winston.Logger` has no constructor
