Exactly 2 forward slashes between the host+port & path is not normalizing to 1 forward slash

You can see it by adding the following test cases:

```
t.is(normalizeUrl('http://sindresorhus.com:5000///foo'), 'http://sindresorhus.com:5000/foo'); // passes
t.is(normalizeUrl('http://sindresorhus.com///foo'), 'http://sindresorhus.com/foo'); // passes
t.is(normalizeUrl('http://sindresorhus.com:5000//foo'), 'http://sindresorhus.com:5000/foo'); // fails - http://sindresorhus.com:5000//foo
t.is(normalizeUrl('http://sindresorhus.com//foo'), 'http://sindresorhus.com/foo'); // fails - http://sindresorhus.com//foo
```
