Feature request: include error own properties in logged errors
### Expected Behaviour

I expect powertools to log all enumerable properties on an error. It's common to include a code, and extra information about an error. For example, node's fs errors include `code`, `syscall` and `path`. I'd like powertools to log

```json
{
        "name": "Error",
        "location": "",
        "message": "ENOENT: no such file or directory, open 'not a file'",
        "stack": "Error: ENOENT: no such file or directory, open 'not a file'"
        "errno": -2,
        "code": "ENOENT",
        "syscall": "open",
        "path": "not a file"
}
```

If you log a regular object or classs it's properties will be logged, but if the class extends Error only stack, message, location, name, and cause will be logged.

### Current Behaviour

logger does not log any of the errors enumerable properties

### Code snippet

```typescript
import fs from 'fs/promises'

import { Logger } from '@aws-lambda-powertools/logger'

class MyData {
  constructor(public readonly field: string) { }
}
class MyError extends Error {
  constructor(public readonly field: string) {
    super(field)
  }
}


const logger = new Logger();

// node's built in errors include code, syscall and other properties
// powertools doesn't include these when printing the error object.
await fs.readFile("not a file").catch(err => {
  logger.error("fs error", {
    bare: err,
    spread: { ...err },
    json: JSON.parse(JSON.stringify(err)),
  })
})

const myError = new MyError("field");
logger.error("fs error", {
  bare: myError,
  spread: { ...myError },
  json: JSON.parse(JSON.stringify(myError)),
})

const myData = new MyData("field");
logger.error("fs error", {
  bare: myData,
  spread: { ...myData },
  json: JSON.parse(JSON.stringify(myData)),
})
```

Logging an error thrown by node's built in fs module, see that `bare`, which is how most people would log an error, is missing errno, code, syscall, and path metadata.
spread, and json include the metadata, but not the stack trace, message, or location. spread and json show that these are enumerable properties on the object.

```json
{
    "level": "ERROR",
    "message": "fs error",
    "service": "service_undefined",
    "timestamp": "2024-03-07T00:04:23.697Z",
    "bare": {
        "name": "Error",
        "location": "",
        "message": "ENOENT: no such file or directory, open 'not a file'",
        "stack": "Error: ENOENT: no such file or directory, open 'not a file'"
    },
    "spread": {
        "errno": -2,
        "code": "ENOENT",
        "syscall": "open",
        "path": "not a file"
    },
    "json": {
        "errno": -2,
        "code": "ENOENT",
        "syscall": "open",
        "path": "not a file"
    }
}
```

Here's a simple custom error and it has the same problem.
```json
{
    "level": "ERROR",
    "message": "fs error",
    "service": "service_undefined",
    "timestamp": "2024-03-07T00:04:23.699Z",
    "bare": {
        "name": "Error",
        "location": "test.ts:27",
        "message": "field",
        "stack": "Error: field\n    at <anonymous> (test.ts:27:17)"
    },
    "spread": {
        "field": "field"
    },
    "json": {
        "field": "field"
    }
}
```

This is logging a normal class that doesn't extend Error and you can see that `bare` includes the properties I would expect.
```json
{
    "level": "ERROR",
    "message": "fs error",
    "service": "service_undefined",
    "timestamp": "2024-03-07T00:04:23.701Z",
    "bare": {
        "field": "field"
    },
    "spread": {
        "field": "field"
    },
    "json": {
        "field": "field"
    }
}
```

### Steps to Reproduce

The script included above reproduces with powertools 1.18.1 or 2.0.2 on node 20.

### Possible Solution

[HIDDEN]

### Powertools for AWS Lambda (TypeScript) version

2.0.2, 1.18.1

### AWS Lambda function runtime

20.x

### Packaging format used

npm

### Execution logs

```Shell
See above.
```

### Additional contract requirements

- Include an error's enumerable own properties in its logged representation alongside the standard error diagnostic fields.
