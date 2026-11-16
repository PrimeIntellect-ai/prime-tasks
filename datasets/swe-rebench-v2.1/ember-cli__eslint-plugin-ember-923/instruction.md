no-actions-hash fails on class extensions that contain `...`
Error thrown: `Cannot read property 'name' of undefined`

How to trigger:
```
Service.extend({
   ...foo,
})
```

Anything with the spread operator inside a class extension causes a error to be thrown
