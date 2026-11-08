AttributeError: type object 'DataFrame' has no attribute '__rdivmod__'/'__divmod__'
**Note**: Series has these attributes implemented.

### Additional contract requirements

A DataFrame must work with Python's built-in `divmod` both as the left operand (`divmod(df, right)`) and as the right operand (`divmod(left, df`)). For operands that pandas can divide this way, the result is a pair containing the element-wise quotient and remainder DataFrames.
