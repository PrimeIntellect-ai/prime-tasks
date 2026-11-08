Warning position is wrong when the warning is in script and TypeScript parser is used
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have updated to the latest version of the packages.

### What version of ESLint are you using?

8.43.0

### What version of `eslint-plugin-astro` are you using?

0.27.1

### What did you do?

<details>
<summary>Configuration</summary>

```json
{
  "root": true,
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:astro/recommended"
  ],
  "parserOptions": {
    "ecmaVersion": 2022,
    "parser": "@typescript-eslint/parser"
  }
}
```
</details>

```astro
<script>


  const foo = document.querySelector('foo')!
  console.log(foo)
</script>
```


### What did you expect to happen?

`eslint .` outputs
```
4:14  warning  Forbidden non-null assertion  @typescript-eslint/no-non-null-assertion
```

### What actually happened?

`eslint .` outputs
```
2:14  warning  Forbidden non-null assertion  @typescript-eslint/no-non-null-assertion
```

### Link to Minimal Reproducible Example

1. Open https://github.com/sapphi-red-repros/eslint-plugin-astro-script-ts-pos
1. `npm i`
2. `npm run lint`


### Additional comments

The warning position is correct for `.ts` files. So I thought this is a bug in eslint-plugin-astro instead of typescript-eslint.

### Additional contract requirements

For the reported script, the warning is reported at line 4, column 15, not line 2. The original expected-output example lists column 14; for this reproduced warning, column 15 is the intended location.
