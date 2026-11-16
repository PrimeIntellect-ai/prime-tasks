BH doesn't extend client 'js' param when it equal true
BEMJSON
```
bh.match('button', function(ctx) {
    ctx.js({ a: 1 });
});
bh.apply({ block: 'button', js: true });
```

Result should be equal `<div class="button i-bem" onclick='return {"button":{"a":1}}'></div>`
