Easy way to determine if the client or server is at fault
Wouldn't it be great if you could do:

```javascript
error = Boom.notFound()
error.isClient // => true

error = Boom.notImplemented()
error.isClient // => false
```

What do you think?

Alternative approach:

```javascript
error = Boom.notFound()
Boom.isClient(error) // => true

error = Boom.notImplemented()
Boom.isClient(error) // => false
```
