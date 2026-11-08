Global context with request argument
When global context was first suggested in #4, functions that generate context could have a `request` argument. Like this :

```js
server.views({
  context: function (request) {
    return {
      version: '1.4.5',
      date: Date.now(),
      id: request.id
    }
  }
});
```

But it is not actually implemented now, and I think that idea is quite essential in many cases of developments.
