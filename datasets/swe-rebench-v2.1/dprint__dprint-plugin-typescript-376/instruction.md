Add ability to force the import statement in one line
What about adding options to keep the import statement always on one line. [There is a discussion](https://github.com/prettier/prettier/issues/5995) for Prettier.

### Additional contract requirements

The same forcing behavior must also be available for export declarations.

When `importDeclaration.forceSingleLine` is enabled, an import declaration is kept on a single line even when it contains multiple named specifiers, unless it contains a line comment or a multi-line block comment, in which case it is formatted across multiple lines as usual.

When `exportDeclaration.forceSingleLine` is enabled, an export declaration is kept on a single line even when it contains multiple named specifiers, unless it contains a line comment or a multi-line block comment, in which case it is formatted across multiple lines as usual.
