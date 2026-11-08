Arguments broken when using something like PM2
Roosevelt won't source arguments when using something like [PM2](https://github.com/Unitech/pm2). This is due to this [block](https://github.com/rooseveltframework/roosevelt/blob/master/lib/sourceFlags.js#L8-L11) of code.

When using PM2 arguments look like this

```
[ '/usr/bin/node',
  '/usr/lib/node_modules/pm2/lib/ProcessContainerFork.js',
  '--development-mode' ]
```

The source name `app.js` in this case is not in the argument list, so `--development-mode` never gets sourced

### Additional contract requirements

- Roosevelt sources command-line flags even when the application source name is not present in the argument list (for example when the process is launched by a process manager such as PM2).
- Roosevelt accepts an `ignoreCLIFlags` boolean parameter (default `undefined`). When `ignoreCLIFlags` is `true`, command-line flags are not parsed, so flags such as `--development-mode` do not affect `params.nodeEnv`; the environment defaults to production.
