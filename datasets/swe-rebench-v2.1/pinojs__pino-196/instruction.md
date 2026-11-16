Child Serializer overwriting parent
Child serializers are overwriting the parent's serializers.

```
var pino = require('pino')

var logger = pino()

var customSerializers = {
  test: function () {
    return 'this is my serializer'
  }
}

var child1 = logger.child({ child: '1', serializers: customSerializers })

var child2 = logger.child({ child: '2' })

logger.info({test: 'should show up'})

child1.info({test: 'should not show up'})

child2.info({test: 'should show up'})
```

results in:
```
{"pid":13537,"hostname":"MacBook-Pro.local","level":30,"time":1487674087287,"test":"this is my serializer","v":1}
{"pid":13537,"hostname":"MacBook-Pro.local","level":30,"time":1487674087289,"test":"this is my serializer","child":"1","v":1}
{"pid":13537,"hostname":"MacBook-Pro.local","level":30,"time":1487674087289,"test":"this is my serializer","child":"2","v":1}
```

I will submit a PR for fix
