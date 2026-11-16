Running tests in node environment
I have `jest-canvas-mock` configured in my package.json:
```
"jest": {
  "setupFiles": [
    "jest-canvas-mock"
  ]
}
```

This is working great for my tests 🎉

However, I'm running some new tests in the [node test environment](https://facebook.github.io/jest/docs/en/configuration.html#testenvironment-string) by using the docblock at the top of the file. In this case `jest-canvas-mock` is throwing an error that window is not defined (which is expected I guess)

Is there any way that the canvas mock can be disabled for jest test files that are run in the node environment?
