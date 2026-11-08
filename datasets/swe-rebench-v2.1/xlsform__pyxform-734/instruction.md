Error if there's a ${ with a space or newline before the next }
A missing } causes particularly bad errors in Collect because it uses ${} notation for placeholders in outputs.

https://forum.getodk.org/t/incomplete-field-reference-in-note-returns-unclear-error/49537

### Additional contract requirements

- Add a public function `validate_pyxform_reference_syntax(value: str, sheet_name: str, row_number: int, key: str) -> None` in module `pyxform.validators.pyxform.pyxform_reference`.
- It returns `None` when the value contains only well-formed PyXForm references.
- It raises `pyxform.errors.PyXFormError` when the value contains a malformed reference. A reference is malformed when a `${` is not closed by a `}`, when the reference name contains a space or newline, when a reference is nested inside another reference, or when a `${` start token is left dangling.
- The raised error message is the public constant `pyxform.validators.pyxform.pyxform_reference.PYXFORM_REFERENCE_INVALID` formatted with the keyword arguments `sheet`, `row_number` and `column`. The formatted message is: `[row : {row_number}] On the '{sheet}' sheet, the '{column}' value is invalid. Reference expressions must only include question names, and end with '}'.`
- Malformed references in XLSForm sheet cells cause XLSForm conversion to fail with that error message.
