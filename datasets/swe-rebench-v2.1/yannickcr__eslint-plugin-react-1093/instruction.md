"no-unused-prop-types" inside async functions (include arrow)
Hi!
I think there is a bug with async functions.
**property**: "no-unused-prop-types"
**parser**: "babel-eslint@7.1.1"
**where**: "async functions"
**example**:
```js
{
  code: [
    'export class Example extends Component {',
    '  static propTypes = {',
    '    failed: PropTypes.func.isRequired,',
    '    loadUserProfile: PropTypes.func.isRequired,',
    '  }',
    '  handleLogin = async () => {',
    '    await this.props.failed();',
    '    await this.props.loadUserProfile();',
    '  };',
    '}'
  ].join('\n'),
  parser: 'babel-eslint'
},
```
