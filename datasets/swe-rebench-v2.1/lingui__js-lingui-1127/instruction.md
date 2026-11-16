ICU select does not generate valid Typescript for keys starting with numbers.
**Describe the bug**
ICU select does not generate valid Typescript for keys starting with numbers.

**To Reproduce**
Given the translation key:

```
msgid "book.name"
msgstr "{id, select, Gen {Genesis} 1John {1 John}  other {____}}"
```

it compiles to:

```
/*eslint-disable*/export const messages={"book.name":[["id","select",{Gen:"Genesis",1John:"1 John",other:"____"}]]};
```

**Expected behavior**
It should quote keys starting with a number, or IMHO every key for simplicity's sake.

```
/*eslint-disable*/export const messages={"book.name":[["id","select",{Gen:"Genesis","1John":"1 John",other:"____"}]]};
```

**Additional context**
Add any other context about the problem here.

- jsLingui version ``lingui --version``
3.10.2

- Babel version ``npm list @babel/core``
```
biblebox-web@20.3.0 /home/peleteiro/Projects/biblebox/web
├─┬ @babel/core@7.14.6
│ └─┬ @babel/helper-compilation-targets@7.14.5
│   └── @babel/core@7.14.6 deduped
├─┬ @babel/plugin-syntax-dynamic-import@7.8.3
│ └── @babel/core@7.14.6 deduped
├─┬ @emotion/react@11.4.0
│ └── @babel/core@7.14.6 deduped
├─┬ @emotion/styled@11.3.0
│ ├── @babel/core@7.14.6 deduped
│ └─┬ @emotion/babel-plugin@11.3.0
│   └── @babel/core@7.14.6 deduped
└─┬ @lingui/cli@3.10.2
  ├── @babel/core@7.14.6 deduped
  └─┬ @babel/plugin-syntax-jsx@7.12.13
    └── @babel/core@7.14.6 deduped
```

- Your Babel config (e.g. `.babelrc`) or framework you use (Create React App, Meteor, etc.)
```
{
  "presets": [
    [
      "next/babel",
      {
        "preset-react": {
          "runtime": "automatic",
          "importSource": "@emotion/react"
        }
      }
    ]
  ],
  "plugins": ["@emotion/babel-plugin", "@babel/plugin-syntax-dynamic-import", "macros"]
}
```
