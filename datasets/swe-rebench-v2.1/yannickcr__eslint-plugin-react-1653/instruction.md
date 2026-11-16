Nested proptypes in FlowType causes RangeError: Maximum call stack size exceeded
I'm guessing this is causing an infinite loop. Not sure is this belongs here or in the [Flow repo](https://github.com/facebook/flow/) (or if I'm just doing things wrong). I've got a nested array that looks like this:

```
type Note = {text: string, children?: Note[]}
type Props = {
  notes: Note[]
};
```

Which is throwing `RangeError: Maximum call stack size exceeded`

Here's the full stack (absolute path to project abbreviated as `~`):

```
    at getKeyValue (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:289:25)
    at iterateProperties (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:308:21)
    at buildTypeAnnotationDeclarationTypes (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:441:11)
    at buildTypeAnnotationDeclarationTypes (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:433:20)
    at buildTypeAnnotationDeclarationTypes (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:472:28)
    at ~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:442:54
    at iterateProperties (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:311:11)
    at buildTypeAnnotationDeclarationTypes (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:441:11)
    at buildTypeAnnotationDeclarationTypes (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:433:20)
    at buildTypeAnnotationDeclarationTypes (~/node_modules/eslint-plugin-react/lib/rules/prop-types.js:472:28)
```

I've stuck with a simple `type Props = { notes: Object[] }` for now
