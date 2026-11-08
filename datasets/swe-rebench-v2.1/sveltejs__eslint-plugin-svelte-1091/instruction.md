svelte/no-useless-mustaches breaks on string literals containing `{}`
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have updated to the latest version of the packages.

### What version of ESLint are you using?

9.21.0

### What version of `eslint-plugin-svelte` are you using?

3.0.0

### What did you do?

<details>
<summary>Configuration</summary>

```js
import js from "@eslint/js";
import svelte from 'eslint-plugin-svelte';

export default [
  js.configs.recommended,
  ...svelte.configs['flat/recommended'],
];
```
</details>

```svelte
Example: <code>import {'{ db }'} from '$lib/db'</code>
```


### What did you expect to happen?

`eslint-plugin-svelte` should detect that the string literal contains curly braces, and therefore should be left untouched.

### What actually happened?

```
Error:   61:39  error  Unexpected mustache interpolation with a string literal value  svelte/no-useless-mustaches
```

--fix:

```svelte
Example: <code>import {db} from '$lib/db'</code>
                       ^~ Cannot find name db.
```

### Link to **GitHub Repo** with Minimal Reproducible Example

https://eslint-online-playground.netlify.app/#eNp9kL1uwzAMhF9F4KIlkXc3CDr0LaIMhkUbcvUHSw5SGHr3UpYDJEOyEbjvjkeuEOe+wXtng0ERb2gSQguncF75yhLGxDLPpyac4QAYjXZJ9N4NehRTJFDb4OfEpsiG2Vsm4btCzRQlfEm36zW4MrwSx2CWUbtjlTix0uF9oxUO3WISu0jHKHpfGMWMvbcWnUJ1KJIQe+MHceGD6VLzxPErkVcKp/qh63+7Eam4d1R9LRES0l9ACS1N1qvF0LxlS1B4+8FQUlyvkc5p2WYp2vOVxUpb6VW7tQBVfyPW0h+dr995RQuZpcuQ/wGDdZfc

### Additional comments

_No response_
