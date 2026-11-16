babel-plugin-transform-inline-environment-variables - Blacklist/whitelist?
I've been using `babel-plugin-node-env-inline` for a while when compiling code that is to be used in Node. I'm getting to the point where I would like to inline other environment variables for dead code elimination while not inlining others for use with `dotenv`. Would it make sense to have an optional blacklist/whitelist to specify which environment variables should be inlined or not?

### Additional contract requirements

The plugin accepts an options object with two optional array-valued properties:

- `include`: an array of environment variable names. When this option is present, only `process.env` variables whose name appears in the array are inlined; variables not named in the array are left untouched.
- `exclude`: an array of environment variable names. When this option is present, `process.env` variables whose name appears in the array are not inlined and are left untouched.

When both options are omitted, any `process.env.VAR` whose value is a string literal is inlined.

If a variable name appears in both `include` and `exclude`, it is left untouched.
