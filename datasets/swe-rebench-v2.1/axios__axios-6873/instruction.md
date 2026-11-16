Error: header name must be a non-empty string
### Describe the bug

Error: `header name must be a non-empty string` is thrown we coping empty headers object

I suspect [set method ](https://github.com/axios/axios/blob/5a9134e0995b08cc0817548ed44e79c420c620b7/lib/core/AxiosHeaders.js#L82) of AxiosHeaders do not detect instance properly

Given a code
```typescript
import {AxiosHeaders} from "axios";
const axios = require('axios');

new AxiosHeaders(new axios.AxiosHeaders());
```
Expected: empty headers created
Actual: `header name must be a non-empty string` error thrown

### To Reproduce

Please run the code below to reproduce, I tested on 1.8.x and 1.7.x versions

### Code snippet

```js
import {AxiosHeaders} from "axios";
const axios = require('axios');

new AxiosHeaders(new axios.AxiosHeaders());
```

Run the code
```
esbuild reproduce.ts --bundle --platform=node | node
```

### Expected behavior

an empty headers object created
### Actual behavior

```
Error: header name must be a non-empty string
    at setHeader ([stdin]:15089:15)
    at AxiosHeaders.set ([stdin]:15106:25)
    at new AxiosHeaders ([stdin]:15082:21)
    at [stdin]:17352:1
    at runScriptInThisContext (node:internal/vm:209:10)
    at node:internal/process/execution:118:14
    at [stdin]-wrapper:6:24
    at runScript (node:internal/process/execution:101:62)
    at evalScript (node:internal/process/execution:133:3)
    at node:internal/main/eval_stdin:32:5

Node.js v20.17.0
```


### Axios Version

1.8.3

### Adapter Version

_No response_

### Browser

_No response_

### Browser Version

_No response_

### Node.js Version

20.x

### OS

OSx 15.3.2

### Additional Library Versions

```bash

```

### Additional context/Screenshots

```bash

```
