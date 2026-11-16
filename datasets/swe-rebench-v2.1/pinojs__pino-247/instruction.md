Pino always show custom levels if they were added after the logging level is set
**Here's a test code**

```javascript
const pino = require('pino')({
  level: 'info'
})
pino.addLevel('verbose', 25)
pino.addLevel('silly', 5)

pino.fatal('fatal')
pino.error('error')
pino.warn('warn')
pino.info('info')
pino.verbose('verbose')
pino.debug('debug')
pino.trace('trace')
pino.silly('silly')
```

**Output**
```
{"pid":5484,"hostname":"bruno-All-Series","level":60,"time":1495832557805,"msg":"fatal","v":1}
{"pid":5484,"hostname":"bruno-All-Series","level":50,"time":1495832557806,"msg":"error","v":1}
{"pid":5484,"hostname":"bruno-All-Series","level":40,"time":1495832557807,"msg":"warn","v":1}
{"pid":5484,"hostname":"bruno-All-Series","level":30,"time":1495832557807,"msg":"info","v":1}
{"pid":5484,"hostname":"bruno-All-Series","level":25,"time":1495832557807,"msg":"verbose","v":1}
{"pid":5484,"hostname":"bruno-All-Series","level":5,"time":1495832557807,"msg":"silly","v":1}
```

**Ther last two lines shouldn't be printed.**

The workaround we found is to set the logging level after the addLevel calls:

```javascript
const pino = require('pino')()
pino.addLevel('verbose', 25)
pino.addLevel('silly', 5)
pino.level = 'info'

pino.fatal('fatal')
pino.error('error')
pino.warn('warn')
pino.info('info')
pino.verbose('verbose')
pino.debug('debug')
pino.trace('trace')
pino.silly('silly')
```

I'm not sure whether it is an undocumented requirement or a bug. Either way it would be nice do document or fix it. I wasted a few hours trying to fix it.
