<Plural /> not extracted
**Describe the bug**
When using the `<Plural />` component from `@lingui/macro` the translation is not extracted to the messages file.

**To Reproduce**
Steps to reproduce the behavior, possibly with minimal code sample, e.g:

```jsx
import { Plural } from "@lingui/macro"

export default function App() {
   return <Plural value={pagination.total} one="# Form" other="# Forms" />
}
```

And then run `npx lingui extract`

**Expected behavior**
I expect the messages json file to contain the following line:
` "{0, plural, one {# Form} other {# Forms}}": "{0, plural, one {# Form} other {# Forms}}",`

**Additional context**

- jsLingui version ``lingui --version``:
```
"@lingui/cli": "^2.7.0",
"@lingui/macro": "^2.7.0",
"@lingui/react": "^2.7.0",
```
- Babel version ``npm list babel-core``
`"@babel/core": "^7.1.0"`
- Your Babel config (e.g. `.babelrc`) or framework you use (Create React App, Meteor, etc.)
Using create-react-app (`react-scripts@2.0.4`)
- lingui configuration
```json
  "lingui": {
    "sourceLocale": "en",
    "format": "minimal",
    "localeDir": "<rootDir>/src/locale",
    "srcPathDirs": [
      "src"
    ]
  },
```

Another odd thing is that if I add an empty `<Trans />` component somewhere in the file it does work. So the following code *does* correctly extract the plural translation.
```jsx
import { Plural, Trans } from "@lingui/macro"

export default function App() {
 return (
    <>
      <Trans />
      <Plural value={pagination.total} one="# Form" other="# Forms" />
    </>
  );
}
```
