Object children are rendered as `<undefined>`
```js
import render from "https://esm.sh/preact-render-to-string@5.2.4?deps=preact@10.11.0";
import { h } from "https://esm.sh/preact@10.11.0";
console.log(render(h("div", null, { hello: "world" })));
```

```shell
$ deno run test.ts
<div><undefined></undefined></div>
```

### Additional contract requirements

- Function children must be omitted: rendering `<div>{() => {}}</div>` produces exactly `<div></div>`.
- For the reported object child, rendering `h("div", null, { hello: "world" })` must produce exactly `<div></div>`.
- These requirements apply to both the default renderer and pretty-printing (`render(vnode, {}, { pretty: true })`).
