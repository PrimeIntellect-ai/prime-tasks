Parsing error (',' expected) in <script> with typescript
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have updated to the latest version of the packages.

### What version of ESLint are you using?

8.55.0

### What version of `eslint-plugin-astro` are you using?

0.30.0

### What did you do?

<details>
<summary>Configuration</summary>

`.eslintrc.json` contents:
```json
{
    "env": {
        "browser": true,
        "es2021": true,
        "node": true
    },
    "extends": [
        "eslint:recommended",
        "plugin:@typescript-eslint/recommended",
        "plugin:astro/recommended"
    ],
    "parser": "@typescript-eslint/parser",
    "parserOptions": {
        "ecmaVersion": "latest",
        "sourceType": "module"
    },
    "plugins": [
        "@typescript-eslint"
    ],
    "rules": {
    },
    "overrides": [
        {
            "files": ["*.astro"],
            "parser": "astro-eslint-parser",
            "parserOptions": {
                "parser": "@typescript-eslint/parser",
                "extraFileExtensions": [".astro"]
            },
            "rules": {
            }
        }
    ]
}
```

`package.json` contents:
```json
{
  "name": "radiant-raspberry",
  "type": "module",
  "version": "0.0.1",
  "scripts": {
    "dev": "astro dev",
    "start": "astro dev",
    "build": "astro check && astro build",
    "preview": "astro preview",
    "astro": "astro"
  },
  "dependencies": {
    "@astrojs/check": "^0.3.2",
    "astro": "^4.0.4",
    "typescript": "^5.3.3"
  },
  "devDependencies": {
    "@typescript-eslint/eslint-plugin": "^6.14.0",
    "@typescript-eslint/parser": "^6.14.0",
    "eslint": "^8.55.0",
    "eslint-plugin-astro": "^0.30.0"
  }
}
```
</details>

When running `npx eslint .` on an astro project using typescript and containing a script block like below, eslint reports `Parsing error: ',' expected`. This does **not** happen if the code is instead placed in the component script.

```astro
<script>
	const x = new Map<string, string>();
</script>
```

### What did you expect to happen?

There should be no parsing error, only errors caused by lints.

### What actually happened?

```
❯ npx eslint .

/home/garmelon/tmp/radiant-raspberry/src/pages/index.astro
  19:33  error  Parsing error: ',' expected

✖ 1 problem (1 error, 0 warnings)
```

### Link to Minimal Reproducible Example

https://github.com/Garmelon/astro-eslint-bug-repro

### Additional comments

_No response_

### Additional contract requirements

Diagnostics produced by linting extracted client-side script blocks must refer to their corresponding locations in the original Astro file.
