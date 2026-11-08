"Expected indentation" incorrectly for boolean operand on newline
**Tell us about your environment**
* **ESLint version: 6.7.2**
* **eslint-plugin-vue version: 6.0.1**
* **Node version: 8.16.0**

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```javascript
module.exports = {
	'env': {
		'browser': true,
		'commonjs': true,
		'es6': true,
	},
	'extends': [
		// 'eslint:recommended',
		'plugin:vue/essential',
		// 'plugin:@typescript-eslint/eslint-recommended',
		// 'plugin:cypress/recommended',
	],
	'globals': {
		'Atomics': 'readonly',
		'SharedArrayBuffer': 'readonly',
	},
	'parserOptions': {
		'ecmaVersion': 2018,
		'parser': '@typescript-eslint/parser',
		'sourceType': 'module',
	},
	'plugins': [
		'vue',
		'@typescript-eslint/eslint-plugin',
		'vuetify',
		'cypress',
	],
	'rules': {
		// Unix linebreaks
		'linebreak-style': [
			'error',
			'unix',
		],
		// No bitwise
		'no-bitwise': 'error',
		// Always single quotes
		'quotes': [
			'error',
			'single',
			{
				'allowTemplateLiterals': true,
			}
		],
		// Always semi-colons
		'semi': [
			'error',
			'always',
		],
		// Allow unhandled callback error
		'handle-callback-err': 0,
		// Allow unused vars
		'no-unused-vars': 0,
		// Allow throw literal
		'no-throw-literal': 0,
		// Allow paren-less arrow functions
		'arrow-parens': 0,
		// Allow async-await
		'generator-star-spacing': 0,
		// Allow debugger during development
		'no-debugger': process.env.NODE_ENV === 'production' ? 2 : 0,
		// Allow dangling commas, but don't enforce it
		'comma-dangle': 0,
		// v-for with v-if rule
		'vue/no-use-v-if-with-v-for': [
			'error',
			{
				'allowUsingIterationVar': true,
			},
		],
		// Operator linebreaks
		'operator-linebreak': [
			'error',
			'after',
			{
				'overrides': {
					'?': 'before',
					':': 'before',
				},
			},
		],
		// Indent with tabs
		'indent': [
			'error',
			'tab',
			{
				'SwitchCase': 1,
				'MemberExpression': 1,
				'flatTernaryExpressions': false,
			},
		],
		// Indent with tabs in Vue script tags
		'vue/script-indent': [
			'error',
			'tab',
			{
				'baseIndent': 1,
				'switchCase': 1,
			},
		],
		// Indent with tabs HTML in Vue template tags
		'vue/html-indent': [
			'error',
			'tab',
			{
				'attribute': 1,
				'baseIndent': 1,
				'closeBracket': 0,
				'alignAttributesVertically': true,
				'ignores': [],
			},
		],
		// Vuetify rules
		'vuetify/no-deprecated-classes': 'error',
		'vuetify/grid-unknown-attributes': 'error',
		'vuetify/no-legacy-grid': 'error',
	},
	'overrides': [
		// turn off 'indent' rule for the script tag in Vue files since we have the 'vue/script-indent' rule
		{
			'files': ['*.vue'],
			'rules': {
				'indent': 0,
			},
		},
	],
};
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
```vue
<script>
	export default {
		methods: {
			shouldRefundTooltipShow (transaction) {
				return (
					(
						isPaymentPartiallyRefunded(transaction.refundPayments, transaction.amount) ||
						isPaymentFullyRefunded(transaction.refundPayments, transaction.amount) // TODO this line should pass the linter
					) &&
					(
						transaction.status === PAYMENT_STATUSES.SETTLED ||
						transaction.type === PAYMENT_TYPES.CREDIT_CARD // TODO this line should pass the linter
					)
				);
			},
		},
	};
</script>
```


**What did you expect to happen?**
The two lines with the `// TODO this line should pass the linter` should have passed.

**What actually happened?**
`error  Expected indentation of 5 tabs but found 6 tabs  vue/script-indent`

<img width="882" alt="Screen Shot 2019-12-20 at 11 37 31 AM" src="https://user-images.githubusercontent.com/11578445/71283348-229d9d80-231d-11ea-80fa-39412fd1f85f.png">
