TypeScript definition file not published
The TypeScript definition file is missing from the `files` whitelist and so isn't published to npm. e.g. https://unpkg.com/hello-wasm-jsconfeu@0.1.0/

### Additional contract requirements

- For the default package manifest, `files` must be exactly `["wasm_pack_bg.wasm", "wasm_pack.d.ts"]`, in that order.
