`istanbul-lib-source-maps` does not preserve implicit `else`
When the coverage map is mapped back to sources using `istanbul-lib-source-maps` the implicit `else` gets dropped in the process. [HIDDEN]

https://github.com/istanbuljs/istanbuljs/blob/fb8cb4bb99c9e5d36c8b011338d2ab5d3c72ff9c/packages/istanbul-lib-source-maps/lib/transformer.js#L71-L85

Example of implicit `else` just so that everyone is on the track of what this issue is about:

```js
// Source code
if(condition) {
  method();
}
unrelatedMethod();

// Instrumented
if(condition) {
  coverageMap.b[0]++;
  method();
} else { // Implicit else right here!
  coverageMap.b[1]++;
}
unrelatedMethod();
```

Check the reproduction case below to see how `data.branchMap` and `data.b` loses the `else` branch.

<details>
  <summary>Minimal reproduction case</summary>

Requirements:
```sh
$ npm install istanbul-lib-instrument istanbul-lib-coverage istanbul-lib-source-maps esbuild
$ node -v
> v16.15.1
```

```js
const filename = "/math.ts";

function logBranches(label, coverageMap) {
  console.log(label);
  console.log(JSON.stringify(coverageMap.data[filename].branchMap, null, 2));
  console.log(coverageMap.data[filename].b);
}

async function run() {
  const sourceCode = `
function add(a: number, b: number): number {
    type SomeType = typeof a | string;

    console.log('Running add');

    if(a === 20) {
        return b;
    }
}

add(1, 2);
`;

  const transpiled = require("esbuild").transformSync(sourceCode, {
    loader: "ts",
    sourcemap: true,
    sourcefile: filename,
  });
  transpiled.map = JSON.parse(transpiled.map);

  const instrumenter = require("istanbul-lib-instrument").createInstrumenter({
    produceSourceMap: true,
    autoWrap: false,
    compact: false,
    coverageVariable: "__coverage__",
    coverageGlobalScope: "globalThis",
  });

  const instrumented = instrumenter.instrumentSync(
    transpiled.code,
    filename,
    transpiled.map
  );

  // Run instrumented code to populate globalThis.__coverage__
  eval(instrumented);
  const __coverage__ = globalThis.__coverage__;

  const { createCoverageMap } = require("istanbul-lib-coverage");
  const coverageMap = createCoverageMap(__coverage__);

  const { createSourceMapStore } = require("istanbul-lib-source-maps");
  const sourceMapStore = createSourceMapStore();
  const transformedCoverage = await sourceMapStore.transformCoverage(
    coverageMap
  );

  logBranches("coveragemap before transforming back to sources", coverageMap);
  logBranches("coveragemap after transforming to sources", transformedCoverage);
}

run();
```

Output:

```
$ node index.js
Running add
coveragemap before transforming back to sources
{
  "0": {
    "loc": {
      "start": {
        "line": 3,
        "column": 2
      },
      "end": {
        "line": 5,
        "column": 3
      }
    },
    "type": "if",
    "locations": [
      {
        "start": {
          "line": 3,
          "column": 2
        },
        "end": {
          "line": 5,
          "column": 3
        }
      },
      {  // See here!
        "start": {},
        "end": {}
      }
    ],
    "line": 3
  }
}
{ '0': [ 0, 1 ] }  // See here!

coveragemap after transforming to sources
{
  "0": {
    "loc": {
      "start": {
        "line": 7,
        "column": 4
      },
      "end": {
        "line": 9,
        "column": null
      }
    },
    "type": "if",
    "locations": [
      {
        "start": {
          "line": 7,
          "column": 4
        },
        "end": {
          "line": 9,
          "column": null
        }
      }
       // See here!
    ]
  }
}
{ '0': [ 0 ] } // See here!
```

</details>

Related issues from downstream:
- https://github.com/vitest-dev/vitest/issues/1887
- https://github.com/vitest-dev/vitest/issues/2239
