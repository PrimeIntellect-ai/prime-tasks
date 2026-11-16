Missing converter: no-redundant-jsdoc to jsdoc/no-types
### 💥 Missing Converter

-   `tslint-to-eslint-config` version: 0.3.1
-   `typescript-eslint` version: 2.10.0

#### TSLint Rule Name

no-redundant-jsdoc

#### ESLint Rule Name

jsdoc/no-types

#### Example

````
"no-redundant-jsdoc": true,
````
should be converted to:
```
"jsdoc/no-types": "error"
```
and `eslint-plugin-jsdoc` should be added.
