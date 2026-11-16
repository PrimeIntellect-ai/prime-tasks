开启拼音模式后，"乐"字在姓名中的读音也变了
代码：
  console.log(
    "不开启姓氏模式,曾乐的读音:",
    pinyin("曾乐", {
      toneType: "none",
    })
  );

  console.log(
    "开启姓氏模式,曾乐的读音:",
    pinyin("曾乐", {
      toneType: "none",
      mode: "surname",
    })
  );

结果：
不开启姓氏模式,曾乐的读音: ceng le
开启姓氏模式,曾乐的读音: zeng yue

试了一下其他姓氏也会这样

问：姓氏模式打开应该只会订正姓的读音，而不应该订正名字的读音？请问是否有这个功能呢

### Additional contract requirements

- The `pinyin(word, options?)` function accepts an option `surname` with the values `"all"` and `"head"`.
- `surname: "all"` applies surname matching to the whole input text.
- `surname: "head"` applies surname matching only to the leading character(s) of the input text.
- When `mode` is `"surname"` and `surname` is omitted, `surname` defaults to `"all"`.
