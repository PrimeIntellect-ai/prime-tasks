属性名に予約語が使用できてしまう
属性名に予約語を使用した以下のようなコードが通ってしまうが、
```js
#[class]
let a = 42
```
このコードを見ると意図としては通らないのが正しそう。
https://github.com/aiscript-dev/aiscript/blob/e7e2651ac6928bc2e766cd21a7e4ed5029cd481b/src/parser/plugins/validate-keyword.ts#L88-L96
[HIDDEN]
https://github.com/aiscript-dev/aiscript/blob/e7e2651ac6928bc2e766cd21a7e4ed5029cd481b/src/parser/visit.ts#L8-L11

### Additional contract requirements

- `#[class]` のように、予約語を属性名として使ったコードは構文エラーとして拒否すること。
