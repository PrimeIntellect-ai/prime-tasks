Value of attribute query selector can not contain any . (point) character
**Describe the bug**
Using attributes like `name="offer.email"` are not queryable with happy-dom.

**To Reproduce**
Clone repo and adjust following files and run tests.

QuerySelectorHTML.ts:
```
export default `
	<div class="class1 class2">
		<!-- Comment 1 !-->
		<h1>Heading1</h1>
		<!-- Comment 2 !-->
		<div class="class1 class2">
			<span class="class1 class2" attr1="value1" attr2="word1 word2" attr3="bracket[]bracket" attr4="word1.word2" type="hidden">Span1</span>
			<span class="class1 class2" attr1="value1">Span2</span>
		</div>
	</div>
	<div>
		<!-- Comment 1 !-->
		<h1>Heading1</h1>
		<!-- Comment 2 !-->
	</div>
`.trim();
```

QuerySelector.test.ts, line 231:
```
		it('Returns all elements with matching attribute containing dot char using "[attr4="word1.word2"]".', () => {
			const container = document.createElement('div');
			container.innerHTML = QuerySelectorHTML;
			const elements = container.querySelectorAll('[attr4="word1.word2"]');

			expect(elements.length).toBe(1);
			expect(elements[0]).toBe(container.children[0].children[1].children[0]);
		});
```

**Expected behavior**
Element should be queryable by attribute with point character in it.

**Device:**
 - Version 8.2.3
