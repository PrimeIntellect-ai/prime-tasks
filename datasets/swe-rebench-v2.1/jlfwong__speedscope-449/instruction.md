Could not import the json example into www.speedscope.app
I downloaded [simple.speedscope.json](https://github.com/jlfwong/speedscope/blob/100578c536a3afab39fb6803d28913d12eac29c5/sample/profiles/speedscope/0.0.1/simple.speedscope.json) and tried to import this into www.speedscope.app.

But this gives in Chromium (Firefox didn't work as well):

```
speedscope v1.16.0
speedscope.f27db165.js:30 WebGL initialized. renderer: ANGLE (NVIDIA Corporation, NVIDIA GeForce RTX 3060 Ti/PCIe/SSE2, OpenGL 4.5.0), vendor: Google Inc. (NVIDIA Corporation), version: WebGL 1.0 (OpenGL ES 2.0 Chromium)
speedscope.f27db165.js:183 Failed to load format TypeError: Cannot read properties of undefined (reading 'unit')
    at u (import.8ae8aa3d.js:111:1462)
    at import.8ae8aa3d.js:121:1875
    at Generator.next (<anonymous>)
    at s (import.8ae8aa3d.js:121:780)
DevTools failed to load source map: Could not load content for https://www.speedscope.app/speedscope.f27db165.js.map: HTTP error: status code 404, net::ERR_HTTP_RESPONSE_CODE_FAILURE
DevTools failed to load source map: Could not load content for https://www.speedscope.app/demangle-cpp.1768f4cc.js.map: HTTP error: status code 404, net::ERR_HTTP_RESPONSE_CODE_FAILURE
DevTools failed to load source map: Could not load content for https://www.speedscope.app/import.8ae8aa3d.js.map: HTTP error: status code 404, net::ERR_HTTP_RESPONSE_CODE_FAILURE
DevTools failed to load source map: Could not load content for https://www.speedscope.app/reset.8c46b7a1.css.map: HTTP error: status code 404, net::ERR_HTTP_RESPONSE_CODE_FAILURE
DevTools failed to load source map: Could not load content for https://www.speedscope.app/source-map.438fa06b.js.map: HTTP error: status code 404, net::ERR_HTTP_RESPONSE_CODE_FAILURE
﻿```

### Additional contract requirements

The same evented profile must also import successfully when represented as compact JSON without formatting whitespace.
