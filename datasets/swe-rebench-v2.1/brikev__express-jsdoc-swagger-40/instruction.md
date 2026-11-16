[Enhancement] Security configuration in path method
We need to add the feature of the security method for each endpoint. We've already added the configuration and schemas in this PR #18 so we have to add for the endpoint config.

The API for the user can be:

```js
/**
 * POST /api/v1/song
 * @summary Create new song
 * @security BasicAuth
 */
```

*Note*: BasicAuth is the name we provide in the security options like in this example.

```js
const options = {
  info: {
    version: '1.0.0',
    title: 'Albums store',
    license: {
      name: 'MIT',
    },
  },
  security: {
    BasicAuth: {
      type: 'http',
      scheme: 'basic',
    },
  },
  file: './basic-auth.js',
  baseDir: __dirname,
};
```

Expected son should be like this one in each endpoint:

```js
"security": [
  {
     "BasicAuth": []
  }
]
```

## Tasks

- [ ] Include it as an option in this [function](https://github.com/BRIKEV/express-jsdoc-swagger/blob/master/transforms/paths/index.js#L15).
