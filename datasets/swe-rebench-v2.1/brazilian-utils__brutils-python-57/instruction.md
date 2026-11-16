Add `parse_cpf` method
[HIDDEN] in order to make the name compatible with the [js brutils](https://brazilian-utils.com.br/#/utilities)

### Additional contract requirements

- Add a public function `parse(dirty: str) -> str` in module `brutils.cpf` that returns `dirty` with the formatting symbols `.` and `-` removed, leaving all other characters untouched. No validation is performed.
- Add a public function `parse_cpf` importable as `from brutils import parse_cpf` that returns the input string with the formatting symbols `.` and `-` removed, leaving all other characters untouched. No validation is performed.
