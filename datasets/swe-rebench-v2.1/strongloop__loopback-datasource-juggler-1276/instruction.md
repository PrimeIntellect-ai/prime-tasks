Issue with incorrect include on HasManyThrough relation.
<!--
- Please ask questions at https://groups.google.com/forum/#!forum/loopbackjs or
  https://gitter.im/strongloop/loopback

- Immediate support is available through our subscription plans, see
  https://strongloop.com/api-connect-faqs/
-->

### Bug or feature request

<!--
Mark your choice with an "x" (eg. [x], NOT [*]).
-->

- [x] Bug
- [ ] Feature request

### Description of feature (or steps to reproduce if bug)
There is a bug when someone sends a request with incorrect `include` filter containing "fields" equal to a String instead of an Object/Array on a model that has a relation HasManyThrough.

eg:
```
{
  "include": {
    "relation": "oneExistingRelation",
    "scope": {
      "fields": "dummyStringProperty"
    }
  }
}
```

### Link to sample repo to reproduce issue (if bug)
https://github.com/nikooiko/loopback-sandbox

You just have to `npm start` && send this request:

```
http://0.0.0.0:3000/api/AppUsers?filter=%7B%22include%22%3A%20%7B%22relation%22%3A%20%22roles%22%2C%20%22scope%22%3A%20%7B%22fields%22%3A%20%22dummyField%22%7D%7D%7D
```


### Expected result
Application should probably return the results with the included field containing only the "id" and the "dummyStringProperty"


### Actual result (if bug)
After a request like this the application simply dies after receiving this error:
TypeError: Cannot read property 'toString' of undefined
   at linkManyToMany: ...

(you can see the actual error at provided sandbox).


### Additional information (Node.js version, LoopBack version, etc)
node v7.7.0


### Related issues

Can be related to #951

### Additional contract requirements

- When an include scope's `fields` value is a string, the included records should contain the named field and their `id`, without other unselected fields.
