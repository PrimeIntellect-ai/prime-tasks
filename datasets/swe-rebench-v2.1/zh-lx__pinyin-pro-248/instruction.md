特殊拼音的转换
## bug 描述

```ts
import { convert } from "pinyin-pro";

for (const pinyin of ["m̄", "hm", "ê̄", "ế", "ê̌", "ề"]) {
  console.log(convert(pinyin, { format: "symbolToNum" }));
}
```

这些都没有转换

## 你预期的样子是？

正确加上声调数字

## pinyin-pro 版本号

3.20.3

## 引入方式

Node.js

## 最小成本的复现步骤

如上
