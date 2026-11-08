feat: override openapi json
let the user override the openapi json file. refrain from generating, if:

a) the file is present somewhere, OR
b) the user passes it as a param to Robyn()

### Additional contract requirements

- The `Robyn` constructor accepts an `openapi_file_path` parameter (default `None`).
- When `openapi_file_path` is supplied, the OpenAPI specification is loaded from that JSON file, resolved relative to the application directory (the directory containing the file passed as `file_object`).
- When `openapi_file_path` is not supplied and a file named `openapi.json` exists in the application directory, the specification is loaded from that file.
- When a custom specification is loaded, OpenAPI generation is skipped: routes added to the application afterwards do not modify the loaded specification.
- The loaded specification is exposed as a dictionary at `app.openapi.openapi_spec`.
