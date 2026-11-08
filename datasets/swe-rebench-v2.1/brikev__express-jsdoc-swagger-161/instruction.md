support multiple security annotate
**Is your feature request related to a problem? Please describe.**
A clear and concise description of what the problem is. Ex. I'm always frustrated when [...]
I want to add multiple security.
for example of my case :
I use two request header strings for authentication. `x-access-token` and `x-refresh-token`.
in this case, I cannot implement both authentication in one request.


**Describe the solution you'd like**
A clear and concise description of what you want to happen.
according to official document of [swagger](https://swagger.io/docs/specification/2-0/authentication/)
we can add multiple authentication variable with `and` `or` operator.

I can define multiple of security objects in option.

it will be easy if I can add
```
/**
 * GET /test
 *
 * @summary
 ...
 * @security accessToken | refreshToken
 ...
```
for `or` operator

and

```
/**
 * GET /test
 *
 * @summary
 ...
 * @security accessToken & refreshToken
 ...
```
for `and` operator I guess.

**Describe alternatives you've considered**
A clear and concise description of any alternative solutions or features you've considered.
or at least availabie multiple annotation for security
```
/**
 * GET /test
 *
 * @summary
 ...
 * @security accessToken
 * @security refreshToken
 ...
```
like this.

**Additional context**

this is my options settings for security.
```
{
    info: {
        version: '1.0.0',
        title: 'HR API',
        license: {
            name: 'MIT',
        },
    },
    security: {
        BasicAuth: {
            type: 'http',
            scheme: 'basic',
        },
        accessToken: {
            type: 'apiKey',
            name: 'x-access-token',
            in: 'header'
        },
        refreshToken: {
            type: 'apiKey',
            name: 'x-refresh-token',
            in: 'header'
        }
    },
    filesPattern: [ './routes/*.js' ], // Glob pattern to find your jsdoc files
    swaggerUIPath: `/swagger`, // SwaggerUI will be render in this url. Default: '/api-docs'
    baseDir: __dirname,
    exposeSwaggerUI: true, // Expose OpenAPI UI. Default true
    exposeApiDocs: true, // Expose Open API JSON Docs documentation in `apiDocsPath` path. Default false.
    apiDocsPath: '/v3/api-docs', // Open API JSON Docs endpoint. Default value '/v3/api-docs'.
}
```
for just in case
Add any other context or screenshots about the feature request here.

I am not sure this is already implemented or not, at least i cannot find any example or issues in here.
