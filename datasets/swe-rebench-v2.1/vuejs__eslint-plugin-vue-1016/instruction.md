"ignores": [ "VAttribute" ] doesn't have any affect in tab mode
**Tell us about your environment**
* **ESLint version: 6.5.1**
* **eslint-plugin-vue version: 5.2.3**
* **Node version: v12.11.0**

**Please show your full configuration:**
<details>
<summary>Click to expand</summary>

```json
{
	"env": {
		"commonjs": true,
		"es6": true,
		"node": true
	},
	"extends": [
		"eslint:recommended",
		"plugin:vue/recommended"
	],
	"globals": {
		"Atomics": "readonly",
		"SharedArrayBuffer": "readonly"
	},
	"parserOptions": {
		"ecmaVersion": 2018
	},
	"plugins": [
		"vue"
	],
	"overrides": [
		{
			"files": [ "*.vue" ],
			"rules": {
				"indent": [ "off" ]
			}
		}
	],
	"parser": "vue-eslint-parser",
	"rules": {
		"vue/html-indent": [
			"error",
			"tab",
			{
				"ignores": [
					"VAttribute"
				]
			}
		],
		"vue/script-indent": [ "off" ],
		"vue/max-attributes-per-line": [
			"error",
			{
				"singleline": 2,
				"multiline": {
					"max": 1,
					"allowFirstLine": true
				}
			}
		],
		"vue/html-closing-bracket-newline": [
			"error",
			{
				"singleline": "never",
				"multiline": "never"
			}
		],
		"vue/mustache-interpolation-spacing": [ "error", "always" ],
		"no-control-regex": [ "off" ],
		"no-empty": [
			"error",
			{ "allowEmptyCatch": true }
		],
		"no-extra-parens": [
			"error",
			"all",
			{
				"conditionalAssign": false,
				"returnAssign": false,
				"nestedBinaryExpressions": false,
				"enforceForSequenceExpressions": false
			}
		],
		"no-irregular-whitespace": [
			"error",
			{
				"skipRegExps": true,
				"skipTemplates": true
			}
		],
		"no-template-curly-in-string": [ "error" ],
		"curly": [ "off" ],
		"dot-location": [ "error", "property" ],
		"dot-notation": [ "error" ],
		"eqeqeq": [ "error", "smart" ],
		"no-caller": [ "error" ],
		"no-case-declarations": [ "error" ],
		"no-else-return": [ "error" ],
		"no-eval": [ "error" ],
		"no-extend-native": [ "error" ],
		"no-extra-bind": [ "error" ],
		"no-fallthrough": [
			"error",
			{ "commentPattern": "[Bb]reak[\\s\\w]*[Oo]mitted" }
		],
		"no-global-assign": [ "error" ],
		"no-implied-eval": [ "error" ],
		"no-loop-func": [ "error" ],
		"no-octal-escape": [ "error" ],
		"no-octal": [ "error" ],
		"no-self-compare": [ "error" ],
		"no-useless-call": [ "error" ],
		"no-warning-comments": [
			"warn",
			{
				"terms": [ "todo", "fixme", "xxx" ],
				"location": "start"
			}
		],
		"radix": [ "error" ],
		"require-await": [ "error" ],
		"wrap-iife": [ "error", "inside" ],
		"array-bracket-newline": [
			"error",
			{
				"multiline": true,
				"minItems": 2
			}
		],
		"array-bracket-spacing": [ "error", "always" ],
		"array-element-newline": [ "error", "consistent" ],
		"block-spacing": [ "error" ],
		"brace-style": [
			"error",
			"1tbs",
			{ "allowSingleLine": true }
		],
		"capitalized-comments": [ "warn", "always" ],
		"comma-dangle": [ "error", "always" ],
		"comma-spacing": [
			"error",
			{
				"before": false,
				"after": true
			}
		],
		"comma-style": [ "error", "last" ],
		"computed-property-spacing": [ "error", "never" ],
		"func-call-spacing": [ "error", "never" ],
		"function-paren-newline": [ "error", "consistent" ],
		"indent": [
			"error",
			"tab",
			{
				"SwitchCase": 1
			}
		],
		"key-spacing": [
			"error",
			{
				"beforeColon": false,
				"afterColon": true,
				"mode": "strict",
				"align": {
					"beforeColon": false,
					"afterColon": true,
					"on": "colon"
				}
			}
		],
		"keyword-spacing": [
			"error",
			{
				"before": true,
				"after": true
			}
		],
		"new-parens": [ "error" ],
		"newline-per-chained-call": [
			"error",
			{ "ignoreChainWithDepth": 2 }
		],
		"no-mixed-operators": "error",
		"no-mixed-spaces-and-tabs": [ "error", "smart-tabs" ],
		"no-trailing-spaces": [ "error" ],
		"no-unneeded-ternary": [
			"error",
			{ "defaultAssignment": false }
		],
		"object-curly-newline": [
			"error",
			{ "consistent": true }
		],
		"object-curly-spacing": [ "error", "always" ],
		"one-var": [ "error", "consecutive" ],
		"operator-assignment": [ "warn", "always" ],
		"semi": [
			"error",
			"always",
			{ "omitLastInOneLineBlock": true }
		],
		"semi-spacing": [
			"error",
			{
				"before": false,
				"after": true
			}
		],
		"semi-style": [ "error", "last" ],
		"quotes": [
			"error",
			"single",
			{ "avoidEscape": true }
		],
		"space-before-function-paren": [
			"error",
			{
				"anonymous": "always",
				"named": "never",
				"asyncArrow": "always"
			}
		],
		"space-in-parens": [ "error", "never" ],
		"space-infix-ops": [ "error" ],
		"switch-colon-spacing": [ "error" ],
		"wrap-regex": [ "error" ]
	}
}
```
</details>

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
```vue
<template>
	<div class="page">
		<div class="page__header">
			<nav class="nav">
				<ul class="nav__container">
					<li class="nav__item">
						<router-link to="/"
									 class="nav__link">
							Home
						</router-link>
					</li>
					<li class="nav__item">
						<router-link to="/about"
									 class="nav__link">
							About
						</router-link>
					</li>
					<li class="nav__item">
						<router-link to="/contact"
									 class="nav__link">
							Contact
						</router-link>
					</li>
					<li class="nav__item">
						<router-link to="/blog"
									 class="nav__link">
							Blog
						</router-link>
					</li>
				</ul>
			</nav>
		</div>
		<div class="page__content-container">
			<router-view class="page__content" />
		</div>
		<div class="page__footer">
			<!-- Todo -->
		</div>
	</div>
</template>
```

**What did you expect to happen?**
Code should pass the check, because I using `"ignores": [ "VAttribute" ]`.

**What actually happened?**
```
   8:10  error  Expected "\t" character, but found " " character  vue/html-indent
  14:10  error  Expected "\t" character, but found " " character  vue/html-indent
  20:10  error  Expected "\t" character, but found " " character  vue/html-indent
  26:10  error  Expected "\t" character, but found " " character  vue/html-indent
```

PS: GitHub has 8-space tab, actual code looks like:
<details>
<summary>Screenshot</summary>

![image](https://user-images.githubusercontent.com/8970959/67202423-445bd080-f411-11e9-8120-70595a07778e.png)
</details>
