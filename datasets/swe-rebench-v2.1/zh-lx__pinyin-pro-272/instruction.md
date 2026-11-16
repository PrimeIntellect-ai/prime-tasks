html api ：是否可以增加去掉 <rp> 标签生成的选项
## 功能描述

是否可以增加去掉 <rp> 标签生成的选项

减少数据量，不需要关注旧浏览器的情况

### Additional contract requirements

- The `html(text, options?)` API must support an `rp` option. Setting `rp` to `false` omits the generated `<rp>` tags around ruby annotations while retaining the pinyin annotations.
