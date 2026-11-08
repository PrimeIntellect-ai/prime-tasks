no-danger-with-children exception when props contains spread
#768 fixed #767 directly by allowing `{...props}` on JSX elements, but it's getting tripped up when it goes to find the definition of `props` and finds spreads there.

```js
// .eslintrc.js
module.exports = {
	"root": true,
	"parserOptions": {
		"ecmaVersion": 6,
		"ecmaFeatures": {
			"experimentalObjectRestSpread": true,
			"jsx": true
		}
	},
	"plugins": ["react"],
	"rules": {
		"react/no-danger-with-children": "error"
	}
};
```

```jsx
// pass.jsx
const props = { foo: 42 };
(<div {...props}>Children</div>);
```

```jsx
// fail1.jsx
const { a, b, ...props } = this.props;
(<div {...props}>Children</div>);
```

```jsx
// fail2.jsx
const props = { foo: 42, ...rest };
(<div {...props}>Children</div>);
```

```sh
$ npm ls --depth=0
~/test
├── eslint@3.3.1
└── eslint-plugin-react@6.1.1

$ node_modules/.bin/eslint pass.jsx
$ node_modules/.bin/eslint fail1.jsx
Cannot read property 'find' of undefined
TypeError: Cannot read property 'find' of undefined
    at findObjectProp (~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:28:29)
    at ~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:46:20
    at Array.find (native)
    at findJsxProp (~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:40:25)
    at EventEmitter.JSXElement (~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:66:14)
    at emitOne (events.js:96:13)
    at EventEmitter.emit (events.js:188:7)
    at NodeEventGenerator.enterNode (~/test/node_modules/eslint/lib/util/node-event-generator.js:40:22)
    at CodePathAnalyzer.enterNode (~/test/node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:608:23)
    at CommentEventGenerator.enterNode (~/test/node_modules/eslint/lib/util/comment-event-generator.js:97:23)
$ node_modules/.bin/eslint fail2.jsx
Cannot read property 'name' of undefined
TypeError: Cannot read property 'name' of undefined
    at ~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:29:24
    at Array.find (native)
    at findObjectProp (~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:28:30)
    at ~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:46:20
    at Array.find (native)
    at findJsxProp (~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:40:25)
    at EventEmitter.JSXElement (~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:66:14)
    at emitOne (events.js:96:13)
    at EventEmitter.emit (events.js:188:7)
    at NodeEventGenerator.enterNode (~/test/node_modules/eslint/lib/util/node-event-generator.js:40:22)
```
