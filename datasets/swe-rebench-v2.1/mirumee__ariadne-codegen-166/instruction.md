Feature request: support Apollo Federation
```
File "/.venv/lib/python3.11/site-packages/ariadne_codegen/schema.py", line 93, in get_graphql_schema_from_path
    schema: GraphQLSchema = build_ast_schema(graphql_ast)
                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/.venv/lib/python3.11/site-packages/graphql/utilities/build_ast_schema.py", line 45, in build_ast_schema
    assert_valid_sdl(document_ast)
  File "/.venv/lib/python3.11/site-packages/graphql/validation/validate.py", line 119, in assert_valid_sdl
    raise TypeError("\n\n".join(error.message for error in errors))
TypeError: Unknown directive '@key'.

Unknown directive '@extends'.

Unknown directive '@external'.
```

Maybe support `assume_valid = true` or/and `assume_valid_sdl = true` in `pyproject.toml` ?
