Class Name Format
Add support for pascal case to Class Name Format linter.
https://github.com/sasstools/sass-lint/blob/master/docs/rules/class-name-format.md

It would be nice to support a naming convention like [SUIT CSS](https://github.com/suitcss/suit/blob/master/doc/naming-conventions.md).

### Additional contract requirements

- The `convention` option of `class-name-format` accepts the value `pascalcase`.
- With `convention: pascalcase`, a class name is accepted only when it starts with an uppercase letter and every following character is a letter or a digit (for example `Pascal`, `APascalCase`, `Card2`). Any other class name, such as `camelCase`, `snake_case`, `hyphenated-name` or `123`, is reported as a warning.
