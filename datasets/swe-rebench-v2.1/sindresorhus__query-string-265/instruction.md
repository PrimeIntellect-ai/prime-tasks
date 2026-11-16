Existing query params in URL get sorted even when sort is disabled for stringifyUrl
Is the following expectation correct ?

```js
test('stringify URL without sorting params', t => {
	t.deepEqual(queryString.stringifyUrl({
        url: 'https://foo.bar?C=3&A=1', query: {D: 4, B: 2}}, {sort: false}),
             'https://foo.bar?C=3&A=1&D=4&B=2');
});
```

Currently the above test will fail because the query parameters that are already present in the URL get sorted, giving

```
'https://foo.bar?A=1&C=3&D=4&B=2'
```
