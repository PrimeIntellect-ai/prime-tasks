dayjs.diff 错误
**Describe the bug**
A clear and concise description of what the bug is.
```js
ERROR
Cannot read properties of undefined (reading '$localOffset')
```

**Expected behavior**

[HIDDEN]

```js
const timezoneOffset = 8
const endTime = dayjs('2023/08/25 10:35', 'YYYY/MM/DD HH:mm').utcOffset(8, true)
const now = dayjs().utcOffset(timezoneOffset)

const diff = endTime.diff(now, 'second')
```

但是只需要改成下面这样，去掉 dayjs 的时间格式，`endTime`对象就会有一个为空对象`{}`的`$x`属性。就能正常使用

```js
const timezoneOffset = 8
const endTime = dayjs('2023/08/25 10:35').utcOffset(8, true)
const now = dayjs().utcOffset(timezoneOffset)

const diff = endTime.diff(now, 'second')
```
**Information**
 - Day.js Version v1.11.9
 - OS: macOS
 - Browser chrome 116
 - Time zone: GMT+8:00

### Additional contract requirements

- Calling `diff(now, 'second')` on a Day.js object created by parsing a string with an explicit format and then given a UTC offset with `utcOffset(8, true)` must complete and return the difference in seconds, rather than throwing an error.
