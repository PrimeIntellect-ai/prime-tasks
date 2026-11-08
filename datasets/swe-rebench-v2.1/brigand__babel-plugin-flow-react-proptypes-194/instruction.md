PropTypes are not added to class components with intersected type parameters
For example, no propTypes will be assigned to this class:

```jsx
var React = require('react');

type FooProps = {
  a_number: number
}

export default class Foo extends React.Component<FooProps & {
  b_number: number
}> {
}
```

Instead, the snippet above just gets translated into something like this:

```jsx
var React = require('react');

let Foo = class Foo extends React.Component {};
export { Foo as default };
```

### Additional contract requirements

- For the example above, the generated JavaScript must assign `Foo.propTypes` with required number validators for both `a_number` and `b_number`, including properties declared in either constituent of the intersection.
