Can't create selector with spaces
```js
const result = parser(selectors => {
	const newSelector = parser.selector({ spaces: { before: ' ', after: ' ' } });
	newSelector.append(parser.tag({ value: 'span' }));
	selectors.append(newSelector);
}).process('div').result;

console.log('|' + result + '|');
```
Console output:
>|div,span|

---
postcss-selector-parser: 2.1.1
