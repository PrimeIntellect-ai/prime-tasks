TypeError: Cannot read property 'json' of undefined
Hi. I got error

```package.json
   "frisby": "^2.0.14",
    "jest": "^22.4.3",
```

```
    TypeError: Cannot read property 'json' of undefined

      at node_modules/frisby/src/frisby/spec.js:261:74
```


I doubt that _response(FrisbyResponse) becomes undefined when FrisbySpec throws Error before `new FrisbyResponse`
https://github.com/vlucas/frisby/blob/master/src/frisby/spec.js#L127-L133
