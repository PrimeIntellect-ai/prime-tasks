t.update module: $apply doesn't play well with dates and regexps
The following test throws `undefined is not a function`:

```js
it('should $apply dates', function () {
  var instance = new Date(1973, 10, 30);
  var actual = update(instance, { $apply: function (date) { return date.getFullYear(); } });
  assert.equal(actual, 1973);
});
```

The following test throws `undefined == 'a'`

```js
it('should $apply regexps', function () {
  var instance = /a/;
  var actual = update(instance, { $apply: function (regexp) { return regexp.source; } });
  assert.equal(actual, 'a');
});
```

[HIDDEN]
