no-danger-with-children exception with spread props
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
<div />
```

```jsx
// fail.jsx
<div {...props} />
```

```sh
$ npm ls --depth=0
~/test
├── eslint@3.3.0
└── eslint-plugin-react@6.1.0

$ node_modules/.bin/eslint pass.jsx
$ node_modules/.bin/eslint fail.jsx
Cannot read property 'name' of undefined
TypeError: Cannot read property 'name' of undefined
    at ~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:29:34
    at Array.find (native)
    at EventEmitter.JSXElement (~/test/node_modules/eslint-plugin-react/lib/rules/no-danger-with-children.js:28:41)
    at emitOne (events.js:96:13)
    at EventEmitter.emit (events.js:188:7)
    at NodeEventGenerator.enterNode (~/test/node_modules/eslint/lib/util/node-event-generator.js:40:22)
    at CodePathAnalyzer.enterNode (~/test/node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:608:23)
    at CommentEventGenerator.enterNode (~/test/node_modules/eslint/lib/util/comment-event-generator.js:97:23)
    at Controller.traverser.traverse.enter (~/test/node_modules/eslint/lib/eslint.js:895:36)
    at Controller.__execute (~/test/node_modules/estraverse/estraverse.js:397:31)
```
