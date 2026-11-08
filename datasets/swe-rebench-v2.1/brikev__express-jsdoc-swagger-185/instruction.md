[BUG] the generic filesPattern: './**/*.js' don't work
**Describe the bug**
As specified in the doc, I would like to be able to use a generic filesPattern. Using filesPattern: './**/*.js', it's not work. However, if I specify the "./app.js" file, the route is well documented.

**To Reproduce**
My app.js:
```
const express = require('express');
const expressJSDocSwagger = require('express-jsdoc-swagger');

const options = {
  info: {
    version: '1.0.0',
    title: 'Albums store',
    license: {
      name: 'MIT'
    }
  },
  security: {
    BasicAuth: {
      type: 'http',
      scheme: 'basic'
    }
  },
  baseDir: __dirname,
  filesPattern: './**/*.js',
  swaggerUIPath: '/api-docs',
  exposeSwaggerUI: true,
  exposeApiDocs: true,
  apiDocsPath: '/v3/api-docs',
  notRequiredAsNullable: false,
  swaggerUiOptions: {},
};

const app = express();
const PORT = 3000;

expressJSDocSwagger(app)(options);

/**
 * GET /api/v1
 * @tags Book
 * @summary This is the summary of the endpoint
 * @return {object} 200 - success response
 */
app.get('/api/v1', (req, res) => res.json({
  success: true,
}));

app.listen(PORT, () => console.log('Example app listening at http://localhost:${PORT}'));
```

**Screenshots**
With filesPattern: './**/*.js'
![image](https://user-images.githubusercontent.com/90182489/132188060-efbf8907-49ea-4ea5-8d3b-99f66e3e5f33.png)

With filesPattern: './app.js'
![image](https://user-images.githubusercontent.com/90182489/132187689-262aee97-a3dd-48e7-b9d0-7e3d00a60e2a.png)

**Desktop (please complete the following information):**
 - OS: Windows
 - Version 10

### Additional contract requirements

When `filesPattern` is `./**/*.js`, JavaScript files in nested directories under `baseDir` must be discovered, and JSDoc-described routes in those files must appear in the generated Swagger paths.
