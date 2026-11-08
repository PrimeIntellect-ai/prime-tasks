Update to > v6 causes `jsonPath` errors
In our project we usw `openapi-example-validator` to validate our OpenAPI specfile example. We have a pretty simple command that worked fine with version 5

```
  "scripts": {
    "openapi-enforcer": "node test/api/openapi-enforcer.js",
    "validate-examples": "openapi-examples-validator src/api/docs/content/specs/main.yaml",
    "test": "npm run openapi-enforcer && npm run validate-examples"
  },
```

However, upgrading to > v6 things started to error at the `jsonPath` call

```
> openapi-examples-validator src/api/docs/content/specs/main.yaml

Validating examples
/home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1976
    throw new Error('jsonPath: ' + e.message + ': ' + code);
          ^

Error: jsonPath: func is not a function: @property.match(/[/+]json/)
    at JSONPath._eval (/home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1976:11)
    at /home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1783:[18](https://github.com/pi-hole/FTL/actions/runs/14548155183/job/40816195602?pr=2373#step:5:19)
    at JSONPath._walk (/home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:[19](https://github.com/pi-hole/FTL/actions/runs/14548155183/job/40816195602?pr=2373#step:5:20)06:7)
    at JSONPath._trace (/home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1782:12)
    at JSONPath._trace (/home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1874:17)
    at JSONPath._trace (/home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1726:17)
    at /home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1733:21
    at /home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1910:7
    at Array.forEach (<anonymous>)
    at JSONPath._walk (/home/runner/work/FTL/FTL/node_modules/jsonpath-plus/dist/index-node-cjs.cjs:1909:22)

Node.js v[20](https://github.com/pi-hole/FTL/actions/runs/14548155183/job/40816195602?pr=2373#step:5:21).19.0
```

Any idea how to fix this?
