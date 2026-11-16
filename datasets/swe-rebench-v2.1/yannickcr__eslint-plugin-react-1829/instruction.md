`react/no-unused-state` warning in new `getDerivedStateFromProps` methods
**eslint versions**

```
"eslint": "4.19.1",
"eslint-config-airbnb": "16.1.0",
"eslint-loader": "2.0.0",
"eslint-plugin-import": "2.10.0",
"eslint-plugin-jsx-a11y": "6.0.3",
"eslint-plugin-mocha": "5.0.0",
"eslint-plugin-react": "7.7.0",
"extract-text-webpack-plugin": "3.0.2",
```
If the only place you reference state is inside `getDerivedStateFromProps` then the eslint warning triggers for `no-unused-state`.  See the example below:

```
import React, { Component } from 'react';


export default class ESLintExample extends Component {
  static getDerivedStateFromProps(nextProps, prevState) {
    if (prevState.id === nextProps.id) {
      return {
        selected: true,
      };
    }
    return null;
  }
  constructor(props) {
    super(props);
    this.state = {
      // This is giving a warning even though it is used inside
      // getDerivedStateFromProps
      id: 123,
    };
  }

  render() {
    return (
      <h1>{this.state.selected ? 'Selected' : 'Not selected'}</h1>
    );
  }
}
```

### Additional contract requirements

- In `static getDerivedStateFromProps(nextProps, <second parameter>)`, the second parameter is the previous state. Fields read through it (for example `<second parameter>.id`) count as used state, regardless of what that parameter is named.
- Such fields must not be reported as unused when their only reference is through that parameter.
