Invoke local fails if function path contains '.'
# Bug Report

## Description

We output our typescript build to .build directory.
Our functions reference this directory i.e. `handler: .build/handler.doSomething`
invoke splits on '.' and doesn't get our paths correct.
[HIDDEN]

### Additional contract requirements

- When invoking a Node.js handler whose module path contains a dot, local invocation must use the complete module path and invoke the correctly named exported function.
