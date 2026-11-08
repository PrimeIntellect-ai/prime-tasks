Add `parse_cnpj` method
[HIDDEN] in order to make the name compatible with the [js brutils](https://brazilian-utils.com.br/#/utilities)

### Additional contract requirements

- Add a public function `parse(dirty: str) -> str` in module `brutils.cnpj` that removes the CNPJ formatting symbols `.`, `/`, and `-` from its input and preserves every other character unchanged.
- The public name `parse_cnpj` is importable from the `brutils` package and removes the CNPJ formatting symbols `.`, `/`, and `-` from its input while preserving every other character unchanged.
