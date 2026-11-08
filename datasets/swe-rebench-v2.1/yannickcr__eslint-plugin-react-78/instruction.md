Rule proposal: order of component methods
Some people like to order component methods in the order of its lifecycle. This is mentioned in https://reactjsnews.com/react-style-guide-patterns-i-like/ and the example he uses is:

```js
React.createClass({
  displayName : '',
  propTypes: {},
  mixins : [],
  getInitialState : function() {},
  componentWillMount : function() {},
  componentWillUnmount : function() {},
  _onChange : function() {},
  _onCreate : function() {},
  render : function() {}
});
```

The list of lifecycle methods can be found at https://facebook.github.io/react/docs/component-specs.html

### Additional contract requirements

- When a React component’s members are out of order, the lint rule should report a diagnostic: lifecycle-related entries belong before custom methods, and `render` belongs last.
- Lifecycle methods must follow lifecycle progression: `getInitialState`, `componentWillMount`, `componentDidMount`, `componentWillReceiveProps`, `shouldComponentUpdate`, `componentWillUpdate`, `componentDidUpdate`, then `componentWillUnmount`. Omitted lifecycle methods do not affect the ordering of those that are present.
