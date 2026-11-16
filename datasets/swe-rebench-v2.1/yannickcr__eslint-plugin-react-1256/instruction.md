[prop-types] nested flow object type spread crashes
Essentially the same presentation as #1178, but slightly different (nested or alias) case as proven by PR #1254.

-----

```js
Cannot read property 'type' of undefined
TypeError: Cannot read property 'type' of undefined
    at buildTypeAnnotationDeclarationTypes (/Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/rules/prop-types.js:478:25)
    at /Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/rules/prop-types.js:490:54
    at iterateProperties (/Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/rules/prop-types.js:359:11)
    at buildTypeAnnotationDeclarationTypes (/Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/rules/prop-types.js:489:11)
    at /Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/rules/prop-types.js:712:38
    at iterateProperties (/Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/rules/prop-types.js:359:11)
    at markPropTypesAsDeclared (/Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/rules/prop-types.js:707:11)
    at Object.ClassDeclaration (/Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/rules/prop-types.js:876:11)
    at Linter.updatedRuleInstructions.(anonymous function) (/Users/kross/projects/ui/node_modules/eslint-plugin-react/lib/util/Components.js:624:75)
    at emitOne (events.js:101:20)
    at Linter.emit (events.js:191:7)

Process finished with exit code 1
```

I finally debugged my case close enough to add a test that breaks the current `master`.

```js
{
      code: [
        'import type {BasePerson} from \'./types\'',
        'type Props = {',
        '  person: {',
        '   ...$Exact<BasePerson>',
        '   lastname: string',
        '  }',
        '};',
        'class Hello extends React.Component {',
        '  props: Props;',
        '  render () {',
        '    return <div>Hello {this.props.person.firstname}</div>;',
        '  }',
        '}'
      ].join('\n'),
      parser: 'babel-eslint'
    }
```
