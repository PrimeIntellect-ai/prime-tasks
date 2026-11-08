"unsafe-wrap" mode crashes when a type is referenced from a variable
[Here](https://github.com/billyjanitsch/babel-rm-proptypes-crash)'s a minimal repro.

The code below causes the plugin to crash when `mode` is set to `"unsafe-wrap"`:

```js
import * as React from 'react'
import PropTypes from 'prop-types'

const sharedPropType = PropTypes.number

export default class Foo extends React.Component {
  static propTypes = {
    bar: sharedPropType,
  }
}
```

Here's the stack trace:

```
TypeError: @babel/template placeholder "NODE": Property expression of ExpressionStatement expected node to be of a type ["Expression"] but instead got "VariableDeclarator"
    at Object.validate (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/types/lib/definitions/utils.js:128:13)
    at validate (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/types/lib/validators/validate.js:17:9)
    at builder (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/types/lib/builders/builder.js:46:27)
    at Object.ExpressionStatement (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/types/lib/builders/generated/index.js:293:31)
    at applyReplacement (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/template/lib/populate.js:92:29)
    at metadata.placeholders.slice.reverse.forEach.placeholder (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/template/lib/populate.js:42:7)
    at Array.forEach (<anonymous>)
    at populatePlaceholders (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/template/lib/populate.js:40:43)
    at arg (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/template/lib/string.js:22:51)
    at arg (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/template/lib/builder.js:77:14)
    =============
    at PluginPass.Program (/Users/billy/work/babel-rm-proptypes-crash/node_modules/babel-plugin-transform-react-remove-prop-types/lib/index.js:160:31)
    at newFn (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/traverse/lib/visitors.js:193:21)
    at NodePath._call (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/traverse/lib/path/context.js:53:20)
    at NodePath.call (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/traverse/lib/path/context.js:40:17)
    at NodePath.visit (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/traverse/lib/path/context.js:88:12)
    at TraversalContext.visitQueue (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/traverse/lib/context.js:118:16)
    at TraversalContext.visitSingle (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/traverse/lib/context.js:90:19)
    at TraversalContext.visit (/Users/billy/work/babel-rm-proptypes-crash/node_modules/@babel/traverse/lib/context.js:146:19)
```
