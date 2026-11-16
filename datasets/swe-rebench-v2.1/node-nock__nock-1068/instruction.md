allowUnmocked: true + regexp path = interception fail
This sample test will fail, while it shouldn't. Because of `allowUnmocked` option

```js
test('match path using regexp with allowUnmocked', function (t) {
  nock('http://www.test-domain.com', {allowUnmocked: true})
    .get(/regex$/)
    .reply(200, 'Match regex');

  mikealRequest.get('http://www.test-domain.com/resources/regex', function(err, res, body) {
    t.type(err, 'null');
    t.equal(res.statusCode, 200);
    t.equal(body, 'Match regex');
    t.end();
  });
});
```
