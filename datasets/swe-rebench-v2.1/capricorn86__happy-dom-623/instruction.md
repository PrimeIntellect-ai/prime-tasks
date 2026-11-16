Element.matches fails when using non-matching descendant selector on element attached to document
```ts
const element = document.createElement('div');
document.appendChild(element);
expect(element.matches('.nonexistent-class div')).toBe(false);
```

```
TypeError: Cannot read properties of undefined (reading 'split')

  296 |     ): { priorityWeight: number; matches: boolean } {
  297 |             const regexp = new RegExp(CLASS_REGEXP, 'g');
> 298 |             const classList = element.className.split(' ');
	  |                                                 ^
  299 |             const classSelector = selector.split(':')[0];
  300 |             let priorityWeight = 0;
  301 |             let match: RegExpMatchArray;

  at SelectorItem.matchesClass (src/query-selector/SelectorItem.ts:298:39)
  at SelectorItem.match (src/query-selector/SelectorItem.ts:91:24)
  at Function.matchesSelector (src/query-selector/QuerySelector.ts:107:27)
  at Function.matchesSelector (src/query-selector/QuerySelector.ts:113:15)
  at Function.matchesSelector (src/query-selector/QuerySelector.ts:113:15)
  at Function.matchesSelector (src/query-selector/QuerySelector.ts:113:15)
  at Function.match (src/query-selector/QuerySelector.ts:66:24)
  at HTMLElement.matches (src/nodes/element/Element.ts:734:24)
```
