Scopeの定義済み変数の一覧を取得できるように

### Additional contract requirements

- Add a public method `getAll()` on the interpreter scope (the `scope` property of the `AiScript` interpreter). It returns a `Map<string, Value>` mapping every variable name defined in the current scope, including global definitions, to its value.
- Variables that exist only inside a function call or block are not included.
- The returned map is a snapshot: modifying the scope after the call does not change the returned map.
