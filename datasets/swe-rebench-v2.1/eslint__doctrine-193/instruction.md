Permitting numeric keys in parameter names
**What version are you using?**

2.0.0

**What JSDoc comment were you trying to parse?**

```js
/**
 * This tests our support for iterator rest inside an
 * iterator destructure (RestElement)
 *
 * @param {Array} input
 * @param {any} input.0 head of iterator
 * @param {any[]} ...input.xs body of iterator
 *
 * @returns {any[]} rotated such that the last element was the first
 */
```

**What Doctrine options were you using (sloppy, unwrap, etc.)?**

```js
var result = doctrine.parse(comment, {
    // have doctrine itself remove the comment asterisks from content
    unwrap: true,
    // enable parsing of optional parameters in brackets, JSDoc3 style
    sloppy: true,
    // `recoverable: true` is the only way to get error information out
    recoverable: true,
    // include line numbers
    lineNumbers: true
  });
```

**What happened? Include output if possible.**

The parsed tag for `input.0` is

```js
        {
            "title": "param",
            "description": "0 head of iterator",
            "type": {
                "type": "NameExpression",
                "name": "any"
            },
            "name": "input.null"
        },
```

Note that `input.0` is transformed to `input.null` [HIDDEN]

**What did you expect to happen?**

I expected `input.0` to be parsed verbatim, with `0` serving as an array index. I can confirm that JSDoc's allows this syntax:

![image](https://cloud.githubusercontent.com/assets/32314/25157993/1482ff70-2473-11e7-9c13-8da7bfe98850.png)

---

Happy to provide a PR allowing for this syntax - [HIDDEN]

### Additional contract requirements

- Parameter-name parsing must accept numeric array-index components in dotted names and preserve the complete name verbatim. Any text following the parameter name must remain its description.
