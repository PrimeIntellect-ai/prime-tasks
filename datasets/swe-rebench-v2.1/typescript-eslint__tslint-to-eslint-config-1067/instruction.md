Missing tslint-microsoft-contrib converter: no-empty-line-after-opening-brace
### 💥 Missing Converter

-   `tslint-to-eslint-config` version: 2.0.1
-   `typescript-eslint` version: 4.9.1

#### TSLint Rule Name

`no-empty-line-after-opening-brace`

Per https://github.com/typescript-eslint/typescript-eslint/blob/master/packages/eslint-plugin/ROADMAP.md, the equivalent rule is now `padded-blocks`.

#### Package Source

https://github.com/microsoft/tslint-microsoft-contrib

### Additional contract requirements

When converting the enabled TSLint rule `no-empty-line-after-opening-brace`, produce an ESLint `padded-blocks` configuration that prohibits an empty line after an opening brace.
