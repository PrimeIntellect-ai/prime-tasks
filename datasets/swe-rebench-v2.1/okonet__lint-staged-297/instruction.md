Glob issues with 4.2.2 and Prettier
Starting with `lint-staged` version 4.2.2 I have glob issues when using with husky and prettier. Here's my lint-staged config:

```json
"lint-staged": {
  "{app,test,config}/**/*.js": [
    "prettier --single-quote --tab-width 4 --print-width 100 --no-bracket-spacing --write",
    "eslint --fix --max-warnings 0",
    "git add"
  ]
}
```

And here's the error from prettier:
```
husky > npm run -s precommit (node v6.11.3)

 ❯ Running tasks for {app,test,config}/**/*.js
   ✖ prettier --single-quote --tab-width 4 --print-width 100 --no-bracket-spacing --write
     → TypeError: patterns must be a string or an array of strings
     eslint --fix --max-warnings 0
     git add
✖ prettier --single-quote --tab-width 4 --print-width 100 --no-bracket-spacing --write found some errors. Please fix them and try committing again.

Unable to expand glob patterns: {app,test,config}/**/*.js 4 100 /home/user/dev/my-app/app/entity/myEntity.js !**/node_modules/** !./node_modules/**
TypeError: patterns must be a string or an array of strings
```

Anyways, thanks for making this awesome tool and if I have time this weekend I'd be glad to look into this problem myself, just wanted to get this out for others to look at ASAP.

### Additional contract requirements

- The staged file paths must be forwarded to the configured command as arguments.
- The command's own arguments must be forwarded to the underlying script rather than consumed by the launcher. In particular, when a `--` separator is used to delimit the arguments passed to a script, it must be placed before the command's own arguments (so that `kcd-scripts format` is invoked with `format` after the separator).
- Running the shown Prettier command on staged JavaScript files must complete without the reported glob-pattern TypeError.
