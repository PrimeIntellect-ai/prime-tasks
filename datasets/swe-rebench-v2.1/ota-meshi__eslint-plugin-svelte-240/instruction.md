no-trailing-spaces "ignoreComments: true" displays error in html comments
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have updated to the latest version of the packages.

### What version of ESLint are you using?

8.17.0

### What version of `eslint-plugin-svelte` are you using?

2.6.0

### What did you do?

<details>
<summary>Configuration</summary>

```
{
  "extends": ["prettier", "standard"],
  "plugins": ["@typescript-eslint"],
  "parser": "@typescript-eslint/parser",
  "rules": {
    "arrow-parens": ["error", "as-needed"],
    "operator-linebreak": ["error", "before"],
    "no-trailing-spaces": [
      "error",
      {
        "ignoreComments": true
      }
    ]
  },
  "overrides": [
    {
      "files": ["*.svelte"],
      "parser": "svelte-eslint-parser",
      "rules": {
        "import/first": 0,
        "import/no-duplicates": 0,
        "import/no-mutable-exports": 0,
        "import/no-unresolved": 0,
        "import/prefer-default-export": 0,
        "eslint-plugin-html": 0,
        "no-multiple-empty-lines": 0
      }
    }
  ],
  "env": {
    "node": true
  }
}

```
</details>

In my component, I have a code comment with 2 empty spaces at the end if the first line: `...blends in with paragraph  ` in order to support line-breaks when hovering the component and viewing its description.

```svelte
<!-- @component
  InlineButton - A button that blends in with paragraph
  styles, but is interactive.
-->
<button>
  <slot />
</button>
```


### What did you expect to happen?

I would hope ESLint would be ok with it, given my config. No errors appear in my `.js` files.

### What actually happened?

Trailing spaces not allowed. eslint([no-trailing-spaces](https://eslint.org/docs/rules/no-trailing-spaces))

### Link to Minimal Reproducible Example

[https://ota-meshi.github.io/eslint-plugin-svelte/playground/#shortenedhash](https://ota-meshi.github.io/eslint-plugin-svelte/playground/#eJx1VsuS3DYM/BVF52VclePWeivJLf8wF4qCJGYoUuZjZmSX/90N6q0ZH7ZW7AZBEGiA86NUrqbyvfz4Q4jib+X6wVmy8WKL4j9rtKV/U4zOFqL4p6imz9jJWFSGbB0KDTu2vevYFYP0svVy6IoQR0PhjXcUmq0ieamivtGfFyvE58V+LM7Ggb5eyml1KT/Z2UcwLhZf2OrLRHyWb6VPcFm+/yjDjUykmRGdDIKdlO9/vS0UrtHjEqLWnvKpe7LRPkQhY/QaLkjwJStP8ro36mJvhDIuaNuKCrFfKYowSIX1k9235CKHdoIDmWbxsSe1rRHcHunlYwsoiIF8jupgkkKUqqNXQViH3aKmKrUiyjY8czmeF1SdBhJkAgndiMo4dX1pkcspBu8QWdT0ZDNa2WsluGwCn3Ti6RG9FEhxroVQyZtnJ9paXLsmZaCiqJ09G1g4b5JVzKHqtjbkTyau+h/1hisRcaZYcnb2tEayuPutgdEsXHPmQ+d85BCOmRmFu5H3un46kYuGwkrvEjbRtyQhD93awLGulT9titK3UF1lpL2eqGSv1t3tfPwq8zWQJ/MUCMFmQOBc58+HwQDtFV7nbPDUoDgoDSxeNtVscYpnb+Fxa+DCDVH3+jstuXt5+8U4RETKSdKHftny/3L3Rr+MJIDdtduB4jrVU7vMQ+RAjyFSv0du0uiaTQdtpkMU5BR9UohcBDTPpNEGqzkYZzOC0kJbkFpMfkK4VcNoFVex1+hJepBK8LOwSgJ86hAmcmHwh9KuGGKSSKGlVnwn7zac03YytTwRnzGJGcr2eo16YqJ3BpG39FjAPHxa8tvaEKR2kxvCgwSKDgdgirynviJ/ZOapdMCuNO6NjFYSh3BaFpT6YVb/shCqk/z2LPo9koPkKqx3o8cpDdPoqpwzJC2fFI9MoF4vSCONiR1avO1WCAPm5LE1rkL3H0GNZ9efS6DtpK6c6GFFPdYJEhD3DtMpK3bh8NYE4RoIiJQOu5pBTrhAzY/Zb9LR6we35DynIJEoq5W0dBdh7CtnVsRZpyLuATnqHv8pKDmsgWAQI1nGrB6y8bKAvqPjN1tUSZuoNyF7muRNG4C7z2EtWH5Xj6kKr5opdLJ2d4DoR40b1/lt2tygPQJL0stNVbHTQVSEdqVd9+YRWlOzLVAQyi77hAusj3Xm+PXoZGV2UJANXhttkZLxhKI/5b69ZpjHpIM91wvjb37wt1luZEVbemcQ7bZB80Cv8NslD2eym1AWEv2jujN4LCX/ssvfy0weNZk6I4k7NFg5xT6Jlcvq1kShRTg57VbBnz9/AdbxqQU=)

In the playground, the `no-trailing-spaces` rule only has "on" or "off" functionality, without me able to include the `"ignoreComments": true` config.

### Additional comments

I've had good success with this linting tool while programming in Svelte. Thank you for maintaining!

### Additional contract requirements

- Expose the Svelte-aware rule under the public ID `svelte/no-trailing-spaces`. It must accept the `ignoreComments` option; when set to `true`, trailing whitespace in HTML comments is ignored while trailing whitespace elsewhere is still reported.
