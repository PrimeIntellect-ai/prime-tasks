Exclude `_` from TypeScript key enum rendering
#### Reason/Context
Given an enum key such as `something_something` the enum renderer creates the following key `SOMETHING_UNDERSCORE_SOMETHING` even when TS fully supports `SOMETHING_SOMETHING`


#### Description

We need to [HIDDEN] here: https://github.com/asyncapi/modelina/blob/71ac65a5aafd44731f7d421aec88c2ccfbfc2cad/src/generators/typescript/renderers/EnumRenderer.ts#L53

### Additional contract requirements

- TypeScript enum key rendering should preserve underscores in enum values rather than expanding them to `UNDERSCORE`. For example, `something_something` should produce `SOMETHING_SOMETHING`.
