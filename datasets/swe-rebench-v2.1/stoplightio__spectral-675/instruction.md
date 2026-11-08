Of model-description and precompilation of rulesets
**Describe the bug**

The doc states `In your ruleset file you can add extends: "spectral:oas" and you'll get everything from spectral:oas2 and spectral:oas3.`

`model-description` is a rule that exists in two versions: one for oas2 and a different one (but named the same way) for oas3.

Precompiled `oas.json` (under `/rulesets/precompiled/` only contains one instance of `model-description` (which happens to be the oas3 version)

**To Reproduce**

```
$ rm -rf rulesets && yarn build
yarn run v1.15.2
$ copyfiles -u 1 "src/rulesets/oas*/**/*.json" dist && copyfiles -u 1 "src/rulesets/oas*/**/*.json" ./
$ tsc -p ./tsconfig.build.json
$ yarn build.oas-functions && yarn compile-rulesets
$ rollup -c

C:\spectral\dist\rulesets\oas\functions\oasOp2xxResponse.js → dist\rulesets\oas\functions\oasOp2xxResponse.js...
created dist\rulesets\oas\functions\oasOp2xxResponse.js in 3.7s

[...]

C:\spectral\dist\rulesets\oas\functions\refSiblings.js → dist\rulesets\oas\functions\refSiblings.js...
created dist\rulesets\oas\functions\refSiblings.js in 2.7s
$ copyfiles -u 1 "dist/rulesets/oas*/functions/*.js" ./
$ node ./scripts/compile-rulesets.js
Done in 54.43s.

$ cat rulesets/precompiled/oas.json | grep -o "model-description" | wc -l
1
```

**Expected behavior**
An oas ruleset than can be run against oas2 and oas3 specifications

**Screenshots**

![image](https://user-images.githubusercontent.com/92363/66638960-38ecf600-ec16-11e9-98dd-d8cdb7dc0e9f.png)

**Environment (remove any that are not applicable):**

`develop` branch

### Additional contract requirements

The combined `spectral:oas` ruleset must be usable against both OpenAPI 2 (Swagger) and OpenAPI 3 documents, and merging `spectral:oas2` and `spectral:oas3` must not drop either version's model-description behaviour.

To resolve the name collision, the version-specific rules must be exposed under these exact public rule identifiers:

- The OpenAPI 2 ruleset (`spectral:oas2`) exposes the model-description rule as `definition-description`, reporting the message "Definition `description` must be present and non-empty string." for a definition without a description.
- The OpenAPI 3 ruleset (`spectral:oas3`) exposes the model-description rule as `components-schema-description`, reporting the message "Model `description` must be present and non-empty string." for a schema without a description.


- For an OpenAPI 2 definition without a description, report the diagnostic at the definition's path (for example, `['definitions', 'user']`). For an OpenAPI 3 schema without a description, report it at the schema's path (for example, `['components', 'schemas', 'user']`).
