Default headers override custom headers from `url` argument
#### Description
Here we override custom headers (user input aka `...url`) with a default set of headers (aka `...options`) when `url` argument is a object.

https://github.com/sindresorhus/got/blob/8d2e91171509bc2aec71c4483978cfd421ebcf1d/source/normalize-arguments.js#L100-L105

#### Minimal reproducible example of bug

```js
const got = require('got');

const client = got.extend({
    hooks: {
        beforeRequest: [
            async (options) => {
                console.dir('Hook (beforeRequest)', { colors: true });
                console.dir(options.headers, { colors: true });
            }
        ]
    }
});

(async () => {
    try {
        const res = await client.get({
            protocol: 'https:',
            host: 'google.com',
            path: '/',
            headers: {
                'X-Custom-Header': 'some-value'
            }
        });

        console.dir('Requests headers', { colors: true });
        console.dir(res.req.getHeaders(), { colors: true });
    } catch (error) {
        console.dir(error, { colors: true });
    }
})();
```

Output with some `console.log`:

```js
'Before options merging (url.headers)'
{ 'X-Custom-Header': 'some-value' }

'Before options merging (options.headers)'
{ 'user-agent': 'got/9.2.2 (https://github.com/sindresorhus/got)' }

'After options merging'
{ 'user-agent': 'got/9.2.2 (https://github.com/sindresorhus/got)' }

'Hook (beforeRequest)'
{ 'user-agent': 'got/9.2.2 (https://github.com/sindresorhus/got)',
  'accept-encoding': 'gzip, deflate' }

'Requests headers'
{ 'user-agent': 'got/9.2.2 (https://github.com/sindresorhus/got)',
  'accept-encoding': 'gzip, deflate',
  host: 'www.google.com' }
```
