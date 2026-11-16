Return user-friendly error when using Node version other than 4.3
current error is:

```
/Users/zfoster/.nvm/v0.10.36/lib/node_modules/shep/lib/commands/build.js:26
const command = exports.command = 'build [env] [functions..]';
^^^^^
SyntaxError: Use of const in strict mode.
```

Best solution likely involves validating against `lambda.json`

### Additional contract requirements

- Instead of failing with a cryptic syntax error, `run` must print a user-friendly warning message to the console when the running Node.js version differs from the AWS Lambda runtime version (Node 4.3.2), and then continue. The warning must mention the Lambda Node version (4.3.2).
