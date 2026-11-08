[Bug]: flat config crash when using manual plugin def and recommended config
### Is there an existing issue for this?

- [X] I have searched the existing issues and my issue is unique
- [X] My issue appears in the command-line and not only in the text editor

### Description Overview

# Repro

```js
// eslint.config.js
import eslintReact from 'eslint-plugin-react';
import eslintReactRecommended from 'eslint-plugin-react/configs/recommended.js';

export default [
	{
		plugins: {
			react: eslintReact,
		},
	},
	eslintReactRecommended,
];
```

`npx eslint eslint.config.js`

# Expected

No errors

# Actual

```
Oops! Something went wrong! :(

ESLint: 8.56.0

Error: Key "plugins": Cannot redefine plugin "react".
```

# More Info

When defining a plugin key in the flat config ESLint enforces that you only ever redefine they key with the same plugin. [This check is done by comparing by reference](https://github.com/eslint/eslint/blob/8e13a6beb587e624cc95ae16eefe503ad024b11b/lib/config/flat-config-schema.js#L361-L363) -- i.e. `configA.plugin.react === configB.plugin.react`

`eslint-plugin-react` fails this check because it defines its "plugin" in two locations:
https://github.com/jsx-eslint/eslint-plugin-react/blob/36e791de784e7fa1edd5b6d232fbcaf2dd7cf9bf/index.js#L14-L31
https://github.com/jsx-eslint/eslint-plugin-react/blob/36e791de784e7fa1edd5b6d232fbcaf2dd7cf9bf/configs/all.js#L23-L26

[HIDDEN]

### eslint-plugin-react version

v7.33.2

### eslint version

v8.56.0

### node version

v20.11.0
