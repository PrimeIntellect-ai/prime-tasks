韵母 iu 转换错误
## bug 描述

```js
describe("convert", () => {
  it("correctly convert for liu2", () => {
    const converted = convert("liu2", { format: "numToSymbol" });
    expect(converted).toEqual("liú");
  })
})
```

<img width="917" alt="image" src="https://github.com/zh-lx/pinyin-pro/assets/31927845/92330901-b0ea-4fd2-bde8-4a720cec3621">

## 你预期的样子是？



## pinyin-pro 版本号

`main` 分支上的

## 引入方式

ES Module

## 最小成本的复现步骤

把如上脚本添加到任一测试文件中
