c('Hello1World')
Seems like the fix to #42 changes the behavior of identifying word breaks after numbers:

Pre 5.3.0:

```
camelcase('Hello1World') === 'hello1World'
```

5.3.0:

```
camelcase('Hello1World') === 'hello1world';
```

I guess it's a matter of opinion, but the previous behavior does seem more like what people would expect. At any rate, if this is the intended behavior, I would have preferred a major version bump.

### Additional contract requirements

- Also, `camelcase('hello1world') === 'hello1World'`.
- The same digit handling applies when the `pascalCase` option is `true`, with the first character of the result uppercased. In particular:
  - `camelcase('Hello1World', {pascalCase: true}) === 'Hello1World'`
  - `camelcase('Hello11World', {pascalCase: true}) === 'Hello11World'`
  - `camelcase('hello1world', {pascalCase: true}) === 'Hello1World'`
  - `camelcase('hello1World', {pascalCase: true}) === 'Hello1World'`
  - `camelcase('hello1', {pascalCase: true}) === 'Hello1'`
  - `camelcase('Hello1', {pascalCase: true}) === 'Hello1'`
  - `camelcase('1hello', {pascalCase: true}) === '1Hello'`
  - `camelcase('1Hello', {pascalCase: true}) === '1Hello'`
