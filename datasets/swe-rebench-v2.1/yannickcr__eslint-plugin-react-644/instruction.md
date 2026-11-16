Detect "function-bind" new syntax in jsx-no-bind
Babel stage-0 implement the ["function-bind"](http://babeljs.io/blog/2015/05/14/function-bind) proposal.
This new syntax offers a `::` suffix operator to make autobind:

```javascript
import React, { Component, PropTypes } from 'react'

export default class Example extends Component {

  state = {
    value: 'hi'
  }

  onInputChange = () => {
    this.setState({
      value: this.refs.value.getValue()
    })
  }

  render () {
    return (
      <input
        type="text"
        ref="value"
        value={this.state.value}
        onChange={::this.onInputChange}/>
    )
  }
}
```

This syntax is handy for React applications, as an alternative to [class properties](https://github.com/jeffmo/es-class-fields-and-static-properties#part-1-class-instance-fields).

But unfortunately, it uses bind (see [babel's ouput](http://babeljs.io/repl/#?evaluate=false&presets=es2015%2Creact%2Cstage-0%2Cstage-2&experimental=true&loose=false&spec=false&playground=false&code=import%20React%2C%20{%20Component%2C%20PropTypes%20}%20from%20%27react%27%0A%0Aexport%20default%20class%20Example%20extends%20Component%20{%0A%0A%20%20state%20%3D%20{%0A%20%20%20%20value%3A%20%27hi%27%0A%20%20}%0A%0A%20%20onInputChange%20%3D%20%28%29%20%3D%3E%20{%0A%20%20%20%20this.setState%28{%0A%20%20%20%20%20%20value%3A%20this.refs.value.getValue%28%29%0A%20%20%20%20}%29%0A%20%20}%0A%0A%20%20render%20%28%29%20{%0A%20%20%20%20return%20%28%0A%20%20%20%20%20%20%3Cinput%0A%20%20%20%20%20%20%20%20type%3D%22text%22%0A%20%20%20%20%20%20%20%20ref%3D%22value%22%0A%20%20%20%20%20%20%20%20value%3D{this.state.value}%0A%20%20%20%20%20%20%20%20onChange%3D{%3A%3Athis.onInputChange}%2F%3E%0A%20%20%20%20%29%0A%20%20}%0A}%0A)) and lead to the same performance issues as fat arrows and bind explicit call.
