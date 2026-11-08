Missing tslint-react rule: jsx-equals-spacing
### Missing Converter

-   `tslint-to-eslint-config` version: 1.0.0-beta

-   `typescript-eslint` version: 2.31.0

#### TSLint Rule Name

jsx-equals-spacing

#### Package Source

**tslint-react**: https://github.com/palantir/tslint-react (see [#rules](https://github.com/palantir/tslint-react#rules))

Equivalents for tslint-react rules generally live in [eslint-plugin-react](https://github.com/yannickcr/eslint-plugin-react). If an ESLint rule equivalent doesn't yet exist, this tslint-to-eslint-config issue can be closed until that equivalent is created.

### Additional contract requirements

When `jsx-equals-spacing` is enabled, its conversion must include the semantically equivalent `react/jsx-equals-spacing` rule from eslint-plugin-react. The enabled TSLint rule must not be reported as missing.
